# deepseek-harness-easyconnect

在 Windows 上，将已经运行的 **Docker EasyConnect HTTP 代理**接入 **DeepSeek Harness**，用于访问校园内的 tju-llm。

请求路径：Harness → 本机 HTTP 代理端口 → Docker EasyConnect → 校园网 → tju-llm。

项目只提供代理启动器。使用者自行准备 Docker EasyConnect、Harness、校园账号和模型权限。这里没有 VPN 镜像、自动登录、余额小窗、浏览器插件、个人配置或 API 密钥。

## 使用条件

- Windows 10/11，Windows PowerShell 5.1 或 PowerShell 7。
- 已安装支持 `HTTP_PROXY` / `HTTPS_PROXY` 的 Harness。开发时检查的本地 CLI 版本为 `0.2.0-rc.2`；其他版本请自行确认代理支持。
- Docker EasyConnect 已启动并登录成功，其 **HTTP 代理端口**已映射到本机。示例映射为 `127.0.0.1:18888:8888`，请使用自己容器实际的端口。
- Harness 内已配置自己的 tju-llm 服务地址、模型名及 API 密钥。若尚未配置，在 Harness 的模型/provider 设置中按校园服务说明填写；本项目不改写该配置，也不切换或回退模型。

参考项目：[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)、[Docker EasyConnect](https://github.com/docker-easyconnect/docker-easyconnect)。

## 三步启动

1. 启动自己的 EasyConnect 容器，在容器提供的登录界面手动登录校园 VPN。关闭此前运行的 Harness 桌面应用或网页版服务器，避免旧进程沿用之前的网络环境。
2. 复制 `config.example.json` 为 `config.local.json`，用文本编辑器填写：

   | 字段 | 填写内容 |
   | --- | --- |
   | `ProxyUrl` | Docker 映射的本机 HTTP 代理 URL；默认 `http://127.0.0.1:18888` |
   | `DesktopPath` | 桌面模式必填：自己的 `DeepSeek Harness.exe` 完整路径 |
   | `DshPath` | 网页模式：自己的 `dsh.cmd` 完整路径；留空时在 PATH 中寻找已安装的 dsh |
   | `Workspace` | 必填：一个已存在的工作目录；建议放在本项目文件夹之外 |
   | `WebPort` | 网页版端口，默认 `3080` |

   JSON 中 Windows 路径可使用 `/`，例如 `D:/Apps/Harness/DeepSeek Harness.exe`，也可使用双反斜杠。只需填写所使用模式的安装路径。若使用桌面安装旁的 CLI，其路径通常是 `dsh-runtime/node_modules/.bin/dsh.cmd`；请以实际安装为准，并保持桌面版与 CLI 的版本兼容。启动器不会自动安装或下载 CLI。

3. 双击 `start-desktop.bat` 或 `start-web.bat`，在 Harness 中选择自己配置的 tju-llm，发送一个简短请求验证。

网页版由 Harness 自己打开带认证的浏览器入口，终端保持运行；停止网页版可按 Ctrl+C。桌面模式关闭 Harness 即可。VPN 容器由使用者管理，退出 Harness 不会停止它。

## 检查与排错

只检查安装路径与本机端口，不启动 Harness：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./start-harness.ps1 -Mode Web -CheckOnly
```

也可传 `-Mode Desktop` 或 `-Config "D:/private/config.local.json"`。

- 代理不可用：检查 Docker 是否启动、容器是否运行、HTTP 端口映射是否正确。SOCKS5 端口不能填入本启动器。
- 代理端口可连接，但模型请求失败：检查 VPN 登录状态、校园服务地址、模型权限和自己的 API 密钥。**端口检查通过不代表 VPN 已登录，也不代表 tju-llm 可用。**
- 桌面程序已运行：包括托盘进程都需要先退出，再通过本启动器启动。
- 网页端口被占用：自行停止旧服务，或换一个 `WebPort`。启动器不会结束已有进程。
- CLI/桌面配置不兼容：检查两者版本，指定兼容的 `DshPath`。

## 代理范围与隐私

代理变量只用于此次启动的 Harness 及其子进程，不修改 Windows 系统代理、用户永久环境变量或主机路由。`localhost`、`127.0.0.1`、`::1` 绕过代理。此次 Harness 进程中支持上述环境变量的其他外部请求也可能经过代理；本启动器不是仅针对 tju-llm 域名的分流规则。

校园账号、密码和 API 密钥请分别在 EasyConnect 和 Harness 中自行输入，**不要放进本项目**。示例配置全部不含凭据；本地配置已加入 `.gitignore`，但忽略规则不能删除已经提交的秘密。Harness 自身仍可能保存会话与凭据，请勿把其用户数据、工作目录、Docker 数据、日志或浏览器配置复制到仓库。

发布包通过 `package.ps1` 的固定文件清单生成，即使本地目录中后来产生其他文件，它们也不会被收进 ZIP。打包脚本同时检查允许发布文件中的常见密钥/凭据格式；这项检查是辅助措施，发布前仍应审阅文件清单。

## 开发与打包

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/test-launcher.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./package.ps1
```

ZIP 写入项目上级目录，文件清单输出到终端。测试使用本机模拟代理和假的 Harness 命令，不登录 VPN、不调用模型、不读取真实凭据。项目按 MIT 许可证提供；第三方 Harness 与 EasyConnect 使用各自许可证。
