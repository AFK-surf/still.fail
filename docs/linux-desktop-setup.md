# Linux 桌面控制：安装与排查 / Linux desktop setup

目标机器需要有图形桌面，并由运行 station 的同一个用户登录。只有命令行、没有图形会话的机器无法共享桌面；still.fail 的浏览器画面仍可在无头模式下使用。

Ubuntu / Debian 的 X11 会话缺少 `ffmpeg` 或 `xdotool` 时，station 会先尝试从系统配置的软件源下载到自己的数据目录，不需要 sudo。下面的系统组件安装需要管理员权限；如果当前用户没有权限，可把对应命令交给机器管理员。安装已有的软件包不会重新配置桌面，但包管理器可能提出依赖变更，请先查看其提示。

## Ubuntu 22.04 / 24.04 或 Debian：GNOME 桌面

在**目标机器**上安装 Wayland 所需的 portal、PipeWire 和采集组件，同时包含 X11 回退需要的图形库：

```sh
sudo apt-get update
sudo apt-get install python3-gi python3-gst-1.0 gir1.2-gstreamer-1.0 \
  gir1.2-gtk-3.0 gir1.2-atspi-2.0 at-spi2-core \
  pipewire gstreamer1.0-pipewire gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  xdg-desktop-portal xdg-desktop-portal-gnome libx11-6 libxtst6
```

如果使用 KDE Plasma，选择系统提供的 `xdg-desktop-portal-kde`，替换上面命令中的 `xdg-desktop-portal-gnome`；实际支持还取决于桌面版本提供的远程桌面 portal。PipeWire 还需要桌面自带的会话管理器，例如 WirePlumber 或 `pipewire-media-session`；机器已有其中一个时，无需切换。

如果 X11 自动准备 `ffmpeg` / `xdotool` 失败，也可以让管理员从配置好的软件源安装：

```sh
sudo apt-get install ffmpeg xdotool
```

## CentOS Stream 9 / 10 或 RHEL 系：GNOME 桌面

在**目标机器**上安装：

```sh
sudo dnf install python3-gobject gtk3 pipewire pipewire-gstreamer \
  gstreamer1-plugins-base gstreamer1-plugins-good \
  xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk \
  at-spi2-core at-spi2-atk libX11 libXtst
```

PipeWire 需要桌面的会话管理器；如果机器尚未安装，可由管理员安装发行版推荐的管理器，例如 `sudo dnf install wireplumber`。已有桌面环境可能已经提供其中大部分组件。CentOS Stream 9/10 的默认源不提供这里使用的 `ffmpeg` / `xdotool` 组合；X11 可以使用上述 GStreamer / XTest 回退。

KDE Plasma 应使用发行版提供的 `xdg-desktop-portal-kde` 后端，包所在的软件源和桌面功能因发行版而异；不要为了这一步自动启用额外软件源。

## 连接桌面

确认目标用户已登录桌面后，在 still.fail 重新打开画面。Wayland 会在目标桌面弹出系统对话框：选择屏幕，并允许远程操作。有的 GNOME 版本需要分别选中键盘和鼠标。安装组件并不能代替这个授权；如果桌面服务尚未启动，保存工作后重新登录图形桌面可能有帮助。

已验证的组合包括 Ubuntu 22.04 GNOME Wayland，以及 CentOS Stream 9 GNOME Wayland、CentOS Stream 9/10 X11；其他桌面和版本取决于其 portal 实现。Wayland 上，如果应用没有可访问的文本输入接口，且系统无法安全映射待输入文字，会显示提示；网页也可通过 still.fail 的浏览器画面操作。

## English

The target needs an active graphical session belonging to the station user. A headless browser can still be used without one. On Ubuntu/Debian X11, the station first tries to prepare `ffmpeg` and `xdotool` in its own data directory without administrator access. The system package commands above require an administrator and are for the **target machine**.

Choose the portal backend for the installed desktop: `xdg-desktop-portal-gnome` for GNOME, or the distribution's `xdg-desktop-portal-kde` for KDE Plasma. PipeWire also needs a session manager such as WirePlumber or the distribution's `pipewire-media-session`; keep the one already in use. After installation, open the screen again and grant screen sharing and remote interaction in the target desktop's dialog. A graphical login may need to be restarted after saving work if the desktop services are not running.

CentOS Stream 9/10's default repositories do not provide the `ffmpeg` / `xdotool` pair used by the original X11 path; the GStreamer / XTest fallback uses the packages shown above. KDE package availability and portal capabilities depend on the distribution and desktop version. See [Ubuntu's portal packages](https://packages.ubuntu.com/jammy/xdg-desktop-portal-gnome) and [Fedora's KDE portal package information](https://packages.fedoraproject.org/pkgs/xdg-desktop-portal-kde/xdg-desktop-portal-kde/) for distribution details.
