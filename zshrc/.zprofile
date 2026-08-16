# ~/.zprofile -- read by zsh on login shells only.
#
# This is the zsh counterpart to ~/.bash_profile. zsh never reads any bash
# startup file, so everything that starts the graphical session has to live
# here or logging in on tty1 gets a bare prompt and no compositor.
#
# ~/.bash_profile is deliberately left in place and working. If zsh causes
# trouble, `chsh -s /usr/bin/bash` and log back in -- the bash path is
# untouched.

if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    # Restrict Hyprland to the AMD iGPU. Without this it starts a second DRM
    # backend on the NVIDIA card, holds /dev/nvidia0 open for the whole session,
    # and the dGPU can never runtime-suspend (~9.4W wasted at 0% utilization).
    #
    # Resolved from the stable PCI path at launch, so it survives card0/card1
    # renumbering across boots. If it ever fails to resolve, the variable is
    # simply not set and Hyprland behaves exactly as it did before.
    #
    # Trade-off: the USB-C/DisplayPort output (card0-DP-1) is wired to the
    # NVIDIA card and will not work while this is set. HDMI and the internal
    # panel are on the AMD card and are unaffected.
    #
    # RECOVERY: if Hyprland fails to start, Ctrl+Alt+F2, log in, and either
    # delete the two lines below or run `chsh -s /usr/bin/bash` to go back to
    # the bash login path entirely.
    # readlink -e (not -f): returns empty unless every component really exists.
    # -c then confirms it resolved to an actual character device node.
    _amd_card=$(readlink -e /dev/dri/by-path/pci-0000:04:00.0-card 2>/dev/null)
    [ -c "$_amd_card" ] && export AQ_DRM_DEVICES="$_amd_card"
    unset _amd_card

    # AQ_DRM_DEVICES only governs which DRM/KMS card Aquamarine drives. EGL
    # vendor loading is separate: libglvnd scans egl_vendor.d in filename order
    # and 10_nvidia.json sorts before 50_mesa.json, so it loads libEGL_nvidia,
    # which opens /dev/nvidia0 and pins the dGPU awake. Restrict EGL to Mesa.
    #
    # Does NOT affect ollama/CUDA (different API) or Vulkan (different loader).
    # It does mean EGL/OpenGL apps cannot render on the NVIDIA card.
    _mesa_egl=/usr/share/glvnd/egl_vendor.d/50_mesa.json
    [ -f "$_mesa_egl" ] && export __EGL_VENDOR_LIBRARY_FILENAMES="$_mesa_egl"
    unset _mesa_egl

    exec start-hyprland
fi

# Work credentials and service config, at mode 600 outside version control.
[ -f ~/.config/secrets.env ] && source ~/.config/secrets.env

# ~/.local/bin is exported from .zshrc, which a TTY login shell does read --
# but only for interactive shells. Emergency tools that must work from
# Ctrl+Alt+F2 (fixlock) live there, so guarantee it here too.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
