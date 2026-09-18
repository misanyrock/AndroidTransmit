# AndroidTransmit 图标

设计：翡翠绿至深青色圆角底板、象牙白文件夹、深青色双向箭头。使用轻微倒角和阴影，保持 32px 时的识别度；外围为真实透明背景。

源文件：`GenerateAppIcon.swift`，使用 AppKit 原生路径与渐变绘制，非第三方素材。初次尝试内置 imagegen 时服务返回额度限制，最终采用独立绘制的原创矢量方案；未使用 API/CLI 图像生成。

在项目根目录重新生成：

```sh
swift -module-cache-path .build/IconModuleCache Design/GenerateAppIcon.swift
```

脚本生成 `Design/AppIcon-1024.png`，并写入 `AndroidTransmit/Assets.xcassets/AppIcon.appiconset` 的全部 10 个 macOS 尺寸槽位。每个尺寸均由同一组矢量路径直接绘制。

最终设计说明：单个 macOS 应用图标；翡翠绿至深青色圆角底板；中心白色文件夹，面板上两条粗线圆角相反方向箭头；无文字、无额外徽章；透明边缘；在小尺寸下保持清晰。
