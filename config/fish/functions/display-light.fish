# ~/.config/fish/functions/display-light.fish
function display-light --description 'Both displays 1080p60, 100% scale, no HDR/WCG (VRAM-light)'
    kscreen-doctor \
        output.HDMI-A-1.mode.22 \
        output.HDMI-A-1.scale.1 \
        output.HDMI-A-1.hdr.disable \
        output.HDMI-A-1.wcg.disable \
        output.DP-1.mode.60 \
        output.DP-1.scale.1 \
        output.DP-1.hdr.disable \
        output.DP-1.wcg.disable
end
