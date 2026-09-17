
# 架构原则

> Java Spring Boot项目的分层架构、模块化设计和包结构规范。

## 系统架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                           体验层                                 │
│        教师应用        学生应用        家长应用                   │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                           网关层                                 │
│    guozhi-gateway (API网关)    guozhi-external-gateway (回调)   │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                           BFF层                                  │
│    guozhi-edu-app (C端应用)    guozhi-ops-app (运营后台入口)     │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                        内部微服务                                 │
├─────────────────────────────────────────────────────────────────┤
│  业务服务                                                        │
│  ├─ guozhi-teaching         课程教学 + 学生成长                   │
│  ├─ guozhi-course-selection 选课服务                              │
│  ├─ guozhi-teacher-development 教师发展                          │
│  └─ guozhi-affairs          教务协同                              │
├─────────────────────────────────────────────────────────────────┤
│  通用服务                                                        │
│  ├─ guozhi-tenant-center    租户数据 + 配置                       │
│  ├─ guozhi-common-platform  流程引擎/表单引擎/资源/审计/消息       │
│  └─ guozhi-third-party      三方集成                              │
├─────────────────────────────────────────────────────────────────┤
│  运营管理                                                        │
│  └─ guozhi-ops-center       运营管理平台                          │
└─────────────────────────────────────────────────────────────────┘
```

### 服务清单

| 分类 | 服务名 | 职责 |
|------|--------|------|
| **网关** | `guozhi-gateway` | API网关，统一入口 |
| | `guozhi-external-gateway` | 外部回调网关 |
| **BFF** | `guozhi-edu-app` | 服务教师/学生/家长应用 |
| | `guozhi-ops-app` | 内部运营管理平台入口 |
| **业务服务** | `guozhi-teaching` | 课程教学服务 + 学生成长服务 |
| | `guozhi-course-selection` | 选课服务 |
| | `guozhi-teacher-development` | 教师发展服务 |
| | `guozhi-affairs` | 教务协同服务 |
| **通用服务** | `guozhi-tenant-center` | 租户数据 + 租户管理员侧配置 |
| | `guozhi-common-platform` | 通用业务服务（流程引擎/表单引擎/资源/审计/消息） |
| | `guozhi-third-party` | 三方集成服务 |
| **运营管理** | `guozhi-ops-center` | 运营管理平台服务 |

## 分层架构原则 (NON-NEGOTIABLE)

| 层级 | 职责 | 禁止 |
|------|------|------|
| **Controller层** | 对外API接口层，负责基本请求参数校验、路由分发 | 不包含业务逻辑 |
| **Job层** | XXL-JOB定时任务执行层，仅处理调度逻辑 | 业务逻辑下沉至Service层 |
| **Service层** | 具体的业务逻辑服务层，实现核心业务规则和流程 | - |
| **Manager层** | 封装第三方服务调用、MQ/Cache等中间件操作、处理Service层间循环依赖、下沉公共业务逻辑 | - |
| **Mapper层** | 数据访问层，仅负责与MySQL数据库交互，使用MyBatis-Plus进行数据持久化 | - |

## 模块化设计原则

| 模块 | 职责 |
|------|------|
| **app模块** | 业务代码存放，Controller层实现api模块定义的接口契约 |
| **api模块** | 存放对外提供的Feign接口定义及相关的Req、Resp、Query对象，定义接口契约并包含完整Swagger注解，作为接口契约层先于app模块实现定义 |
| **config模块** | 配置文件模块，包含所有运行时配置 |
| **assembly模块** | 打包模块，定义部署包组装规则 |

## api模块依赖隔离 (NON-NEGOTIABLE)

- **禁止**微服务的 api 模块依赖任何其他微服务的 api 模块（如 `guozhi-teaching-api` 依赖 `guozhi-affairs-api`）
- 原因：api 是对外契约，被 BFF 和其他服务的 app 模块引用；api 间互相依赖会把对方契约及其传递依赖拖给所有消费者，造成服务间耦合蔓延、发包连锁升级
- 需要对方的数据结构：在本服务 api 内自行定义对应的 Req/Resp/Query 对象，不 import 对方 api 的类
- 需要调用对方服务：由 app 模块依赖对方 api 走 Feign，api 模块不感知其他服务
- 例外：公共框架包（framework）不属于微服务 api，可正常依赖

## 层间调用规范 (NON-NEGOTIABLE)

- **禁止跨层调用**: Controller只能调用Service，Service只能调用Manager和Mapper
- **单向依赖**: 上层可以依赖下层，下层不能依赖上层
- **DTO使用**: Service间调用必须使用DTO对象，禁止传递Entity或Req对象

## URI命名规范 (NON-NEGOTIABLE)

- **URI路径格式**: 所有Controller的URI格式为`/{功能}`
- **单词功能名**: `/tenant`、`/audit`
- **多单词功能名**: 必须使用kebab-case，如`/user-center`、`/get-order`
- **禁止**: camelCase命名多单词路径(如`/getOrder`)，禁止使用/api、/inner、/outer、应用名等前缀

## 接口路径稳定性 (NON-NEGOTIABLE)

- refactor任务禁止修改API接口的URI path（`@RequestMapping`/`@PostMapping`/`@GetMapping`等注解的path值）
- 路径变更属于破坏性变更，须走feature流程而非refactor

## 包结构规范

### app模块

```
app/src/main/java/com/guozhi/api/[项目名称]/[业务名称]/
├── constants/          # 常量类定义
├── controller/         # Controller层
├── job/               # 定时任务
├── mapper/            # Mapper层
│   └── relation/      # 关系型表专用
├── model/             # 模型对象(仅包含entity/enums/dto子包)
│   ├── entity/        # 数据库实体(继承BaseEntity)
│   ├── enums/         # 枚举定义
│   └── dto/           # Service间传参对象(以DTO结尾)
├── service/           # Service层
│   ├── impl/          # Service实现
│   └── manager/       # Manager层
│       └── impl/      # Manager实现
└── utils/             # 工具类
```

### DTO 实体定位规范 (NON-NEGOTIABLE)

- **禁止**在业务子包下新建 model/ 或其它目录放置 DTO（非 DB 对应实体）
- **必须**：非 DB 对应的实体（DTO/传输对象/内部模型）一律创建在当前模块的 `model/dto/` 下
- **命名**：DTO 类名以 `DTO` 结尾（如 `EducationEventAccessDTO`、`SyncResultDTO`）
- **DB 对应性判断**：有数据库表对应 → `model/entity/`（继承 BaseEntity，无后缀）；无表对应 → `model/dto/`（带 DTO 后缀）

### api模块

```
api/src/main/java/com/guozhi/api/[项目名称]/
├── [业务名称]/
│   ├── api/
│   │   └── [业务名称]Api.java                    # Feign API接口定义
│   └── model/
│       ├── query/
│       │   └── [名称]Query.java                  # 查询请求对象
│       ├── request/
│       │   ├── [名称]Req.java                    # 创建、修改请求对象
│       │   └── [批量操作名称]BatchReq.java       # 批量操作请求对象
│       └── response/
│           ├── [名称]Resp.java                   # 返回响应对象
│           └── [批量操作名称]BatchResp.java      # 批量操作响应对象
└── config/
    └── [项目名称]FeignAutoConfiguration.java     # Feign自动配置
```

## Controller层包结构规范 (NON-NEGOTIABLE)

- 所有Controller统一放在controller包下
- **禁止**使用inner/outer、pc/wechatmini等子包结构
- 所有Controller统一使用`/{功能}`路径格式
