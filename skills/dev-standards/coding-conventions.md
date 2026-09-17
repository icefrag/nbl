
# 开发规范

> 本文件所有规则均为 NON-NEGOTIABLE。

## Spring依赖注入

- 使用`@RequiredArgsConstructor` + `final`字段，禁止`@Autowired`/`@Resource`
- 适用：所有Spring Bean（Controller、Service、Manager、Job等）

```java
@RequiredArgsConstructor
public class UserController implements UserApi {
    private final UserService userService;
}
```

## 依赖管理原则 (NON-NEGOTIABLE)

- **版本集中定义**: 所有第三方依赖版本必须在父 pom 的 `<properties>` 和 `<dependencyManagement>` 中集中定义
- **子模块禁止指定版本**: 子模块引用第三方依赖时禁止直接指定版本号（由父 pom 统一管理）
- **例外**: 仅有版本管理的 starter 依赖（如 spring-boot-starter）可由子模块声明版本

## Lombok @Builder

- 所有实体对象（Entity、DTO、Req、Resp、Query等）使用@Builder时，必须同时添加`@AllArgsConstructor`和`@NoArgsConstructor`

## ID生成

- 所有表写入必须使用`IdWorker.getId()`生成主键，禁止UUID/自增/时间戳

```java
entity.setId(IdWorker.getId());
```

## 数据库表设计

**BaseEntity 字段**（继承即可，禁止重复声明）：id(BIGINT)、create_time(DATETIME)、update_time(DATETIME)

**子类 Entity 自行声明**：created_by(BIGINT)、updated_by(BIGINT)、is_deleted(TINYINT, 加`@TableLogic`)

> BaseEntity 详细说明见 CLAUDE.md「BaseEntity 字段范围」和「操作人维护」

## 字段默认值

- 有合理默认值的字段必须 NOT NULL + DEFAULT：
  - 整数/小数：DEFAULT 0
  - 字符串：DEFAULT ''
- 字段为空本身有业务含义时允许 NULL（如生日、结束时间），不设默认值
- text/json 类型不设默认值

## Entity定义

- 所有Entity继承`BaseEntity`，禁止重复定义id、createTime、updateTime、deleted
- is_deleted必须添加`@TableLogic`注解

## 更新操作

- 使用`update(Wrapper)`，通过`LambdaUpdateWrapper`设置更新字段和条件
- 禁止`updateById()`

```java
userMapper.update(new LambdaUpdateWrapper<UserEntity>()
    .eq(UserEntity::getId, userId)
    .set(UserEntity::getName, "newName"));
```

## 批量插入/更新

- 批量写入统一用 `ServiceImpl` 内置方法：插入 `this.saveBatch(list)`、更新 `this.updateBatchById(list)`（JDBC BATCH 模式，默认每 1000 条 flush），禁止循环单条 insert/update

## 查询操作

- 禁止在Service层创建QueryWrapper/LambdaQueryWrapper
- 所有查询在Mapper层用`default`方法封装

```java
default UserEntity selectByGzId(String gzId) {
    return selectOne(new LambdaQueryWrapper<UserEntity>()
        .eq(UserEntity::getGzId, gzId));
}
```

- 表中含tenantId时，按ID查询必须同时过滤tenantId

```java
default UserEntity selectByIdAndTenantId(Long id, Long tenantId) {
    return selectOne(new LambdaQueryWrapper<UserEntity>()
        .eq(UserEntity::getId, id)
        .eq(UserEntity::getTenantId, tenantId));
}
```

## 集合参数查询

- Mapper层`.in()`必须先检查集合是否为空，否则MyBatis-Plus会生成无效SQL

```java
if (CollUtil.isEmpty(ids)) { return Collections.emptyList(); }
```

## 逻辑删除

- MyBatis-Plus已全局启用，查询自动过滤已删除数据，禁止显式设置逻辑删除条件

## JSON操作

- 统一使用`JsonUtil.toJsonString(Object)`和`JsonUtil.toObject(String, TypeReference)`
- 禁止直接使用Gson/Jackson/Fastjson

## EnumUtil

- 路径：`com.guozhi.api.framework.utils.EnumUtil`，适用于所有`IEnum<T>`枚举
- `of()`/`getDescByCode()`/`getCodeByDesc()`
- 禁止枚举类内部手写静态方法遍历values()

## 本地缓存

- 本地缓存统一使用 Guava Cache（`CacheBuilder` 构建），禁止基于`ConcurrentHashMap`自行实现过期/容量淘汰
- 分布式缓存走 Redis，不在此范围

```java
private final Cache<String, User> cache = CacheBuilder.newBuilder()
    .maximumSize(1000)
    .expireAfterWrite(10, TimeUnit.MINUTES)
    .build();
```

## 空值判断

- 禁止手动`!= null` + `isEmpty()/size()`组合判断，统一使用Hutool工具类

| 类型 | 非空判断 | 为空判断 | 路径 |
|------|---------|---------|------|
| String | `StrUtil.isNotBlank(str)` | `StrUtil.isBlank(str)` | `cn.hutool.core.util.StrUtil` |
| Collection/List | `CollUtil.isNotEmpty(list)` | `CollUtil.isEmpty(list)` | `cn.hutool.core.collection.CollUtil` |
| Map | `MapUtil.isNotEmpty(map)` | `MapUtil.isEmpty(map)` | `cn.hutool.core.map.MapUtil` |
| 任意对象 | `ObjectUtil.isNotNull(obj)` | `ObjectUtil.isNull(obj)` | `cn.hutool.core.util.ObjectUtil` |

```java
if (StrUtil.isBlank(name)) { ... }
if (CollUtil.isNotEmpty(ids)) { ... }
if (MapUtil.isEmpty(params)) { ... }
```

## 禁止魔术数字

- 查询条件中的type/status/enabled等值必须使用枚举常量

```java
.eq(GeneralQuality::getType, GeneralQualityTypeEnum.NATIONAL.getCode())
```

## 条件判断禁止魔法值

- switch/if中涉及表达式类型、数据类型、运算符、状态码等业务常量时，必须使用枚举，禁止硬编码字符串

```java
// 禁止
switch (expr.getType()) {
    case "LITERAL":
        return compileLiteral(expr);
}

// 推荐
ExpressionTypeEnum type = EnumUtil.of(ExpressionTypeEnum.class, expr.getType());
switch (type) {
    case LITERAL:
        return compileLiteral(expr);
}
```

## 业务异常处理

- 禁止手动抛RuntimeException及其子类
- 方式一：`WarnAssert.isTrue(expression, message)`
- 方式二：`BizException.wrap(code, message)`
- 错误码优先用已有BaseResponseCode，无匹配用`ClientResponseCode.BAD_REQUEST`

## Controller返回值

- 禁止定义`Response<XX>`/`Result<XX>`包装类型，直接返回业务对象/`List<XX>`/`IPage<XX>`
- 全局异常处理器统一封装

## 分页查询

- 统一返回`IPage<T>`，禁止自定义PageResult等

## FeignClient

- `@FeignClient`必须加`contextId`（用接口类名），禁止`path`
- `@RequestMapping`定义全局URI前缀
- 直接返回业务对象，禁止TypedApiResponse等包装

## @PathVariable禁止

- Controller和FeignClient禁止`@PathVariable`，统一用`@RequestParam`

## HTTP请求方法

- 查询方法用GET，增删改用POST
- Controller入参为对象时必须用`@PostMapping` + `@RequestBody`，禁止`@GetMapping`无注解接收对象（Feign调用需RequestBody序列化）

```java
@PostMapping("/query")
IPage<FormListResp> query(@RequestBody FormPageQuery query);
```

## 日期时间格式

- 统一使用`java.util.Date`，禁止String/LocalDateTime
- `@JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss", timezone = "GMT+8")`

## Long序列化

- Resp 对象中所有 `Long` 字段必须加 `@JsonSerialize(using = ToStringSerializer.class)`，以字符串形式返回给前端
- 原因：雪花ID超过 JS `Number.MAX_SAFE_INTEGER`（2^53），前端按数字解析会精度丢失
- `ToStringSerializer` 路径：`com.fasterxml.jackson.databind.ser.std.ToStringSerializer`

```java
@JsonSerialize(using = ToStringSerializer.class)
@Schema(description = "任务日志 ID")
private Long id;
```

## Swagger注解

- api模块：`@Tag`(接口级)、`@Operation`(方法级)、`@Parameter`(参数级)、`@Schema`(字段)
- app模块Controller不需重复注解，通过实现api接口继承
- 禁止：Controller加`@RequestMapping`、Swagger 2.x注解（`@ApiModel`等）、枚举类加`@Schema`
- `@Schema`属性：description必填、example建议填、requiredMode根据JSR-303确定

## API模型文档一致性

- 修改DTO/Req/Resp字段时，Javadoc注释与`@Schema(description=...)`必须同步更新

## 非BFF服务Req上下文字段

- 适用：除guozhi-edu-app和guozhi-ops-app以外的所有内部微服务
- tenantId/operatorId：`@Schema(hidden = true)`，禁止`@NotNull`或`requiredMode = REQUIRED`（由框架拦截器自动注入）

## BFF Controller 上下文透传

- BFF Controller 调用下游服务前，必须通过`UserHolder`设置Req/Query对象的`tenantId`和`operatorId`
- 写操作（create/update/delete/approve等）：同时设置`tenantId` + `operatorId`
- 读操作（get/page/detail等）：至少设置`tenantId`

```java
// 写操作
req.setTenantId(UserHolder.getTenantIdLong());
req.setOperatorId(UserHolder.getUserId());

// 读操作
query.setTenantId(UserHolder.getTenantIdLong());
```

## Controller日志

- 禁止在Controller层手动打印请求进入/完成日志
- 允许：异常调试日志、业务关键节点日志、性能监控日志

## MQ命名

- Queue：`guozhi_v2_{业务描述}_queue`（如 guozhi_v2_third_auth_event_queue）
- RoutingKey：`guozhi.edu.{业务描述}`（如 guozhi.edu.tenant.lifecycle）

## 类引用

- 禁止使用完整包路径，必须import后直接用类名

## Mapper层XML查询

- 简单查询用MyBatis-Plus内置方法
- 复杂查询（JOIN/动态SQL/聚合/子查询）必须在XML中编写（`src/main/resources/mapper/`）
- 禁止在Service/Manager层拼接SQL

## Service实现

- 单实体 Service 实现类必须 `extends ServiceImpl<XxxMapper, XxxEntity> implements XxxService`
- 获得 IService 全部能力（saveBatch、updateBatchById、getOne、page 等），统一基类

```java
public class UserServiceImpl extends ServiceImpl<UserMapper, UserEntity> implements UserService { }
```

## Service层入参

- Service可直接接收Req对象，无需转DTO
- DTO用于Service间调用传参
