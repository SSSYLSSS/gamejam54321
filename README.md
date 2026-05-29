# 五!四!三!二十一点!

一款改版 21 点卡牌对战博弈游戏，带有 NanoVG 粒子特效和动态背景。

## 游戏规则

### 基本规则
- **5局3胜**，双方各有 54 张牌的独立抽牌堆
- 每局发 5 张手牌，经过 3 回合弃牌换牌后结算
- 结算时比较谁更接近 21 点（绝对值距离，越近越好）

### 回合流程
| 阶段 | 说明 |
|------|------|
| **五!** | 第一回合：可弃置至多 5 张牌，再抽 5 张 |
| **四!** | 第二回合：可弃置至多 4 张牌，再抽 4 张 |
| **三!** | 第三回合：可弃置至多 3 张牌，再抽 3 张 |
| 结算 | 比较双方手牌点数与 21 点的距离 |
| **二!** | 结算后：弃置至多 2 张至自己抽牌堆 |
| **一!** | 结算后：保留至多 1 张至下局手牌 |

### 卡牌点数
- **A** = 1 点, **2~10** = 面值, **J/Q/K** = 0 点
- **鬼牌** = 结算时可选 0~13 点

### 卡牌特效
| 牌面 | 效果 |
|------|------|
| **A** | 结算时翻倍对方同花色牌的点数 |
| 2~6 | 普通牌，无特效 |
| **7** | 不可弃置/修改；拥有 3 张 7 触发特殊胜负规则 |
| **8** | 使自己的普通牌 (2~6) 点数各减 1 |
| 9~10 | 稀有牌，无特效 |
| **J** | 弃置时可从弃牌堆或抽牌堆随机抽一张牌 |
| Q/K | 花牌，0 点无特效 |
| **小王** | 点数可选 0~13；结算前移除对方一张牌 |
| **大王** | 点数可选 0~13；可将自己一张牌视为任意点数 |

## 项目结构

```
scripts/
├── main.lua                    # 主入口 (3D场景 + VFX + UI初始化)
├── core/                       # 核心数据层
│   ├── Card.lua                # 卡牌数据与工具函数
│   ├── Constant.lua            # 枚举常量定义
│   └── Deck.lua                # 牌堆管理
├── model/                      # 数据模型
│   └── GameState.lua           # 游戏状态
├── system/                     # 逻辑系统
│   ├── DiscardSystem.lua       # 弃牌逻辑
│   ├── EffectSystem.lua        # 特效结算系统
│   ├── PhaseSystem.lua         # 阶段流转
│   └── SettlementSystem.lua    # 结算系统
├── service/                    # 服务层
│   ├── AIService.lua           # AI决策
│   └── GameController.lua      # 游戏控制器 (对外接口)
├── ui/                         # UI 层
│   ├── Colors.lua              # 全局颜色定义
│   ├── components/
│   │   └── CardWidget.lua      # 卡牌UI组件 (悬停放大+效果提示)
│   └── scenes/
│       ├── MenuScene.lua       # 主菜单
│       ├── GameScene.lua       # 游戏界面
│       └── SettingsScene.lua   # 设置界面
└── vfx/                        # 视觉特效层
    ├── VFXConfig.lua           # VFX参数配置
    ├── VFXManager.lua          # VFX统一管理器
    ├── ParticleSystem.lua      # NanoVG粒子系统
    ├── BackgroundRenderer.lua  # 动态背景 (星空+光带+暗角)
    └── CardGlow.lua            # 卡牌发光效果
```

## 视觉特效

- **动态背景**: 深色渐变底色 + 流动光带 + 闪烁星星
- **NanoVG 暗角**: 屏幕边缘渐变变暗
- **粒子效果**: 胜利金色烟花 / 失败暗红碎裂 / 弃牌蓝色飞散 / J效果紫色闪光
- **卡牌光晕**: 特殊卡牌呼吸发光 (鬼牌紫 / J蓝紫 / 7绿 / A金)

## 技术栈

- **引擎**: UrhoX (TapTap Spark Editor)
- **语言**: Lua 5.4
- **UI**: urhox-libs/UI (Yoga Flexbox 布局)
- **特效**: NanoVG 矢量图形 + HDR Bloom 模拟
- **后处理**: 3D Scene + DarkNight LightGroup

## 开发

项目基于 TapTap Maker 在线 IDE 开发，使用 `mcp__sce-urhox__build` 构建。
