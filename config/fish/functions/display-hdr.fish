# ~/.config/fish/functions/display-hdr.fish
function display-hdr --description 'S90D 4K@149.88 HDR+WCG + Denon 4K29.88, 200% scale'
    kscreen-doctor \
        output.HDMI-A-1.mode.9 \
        output.HDMI-A-1.scale.2 \
        output.HDMI-A-1.hdr.enable \
        output.HDMI-A-1.wcg.enable \
        output.DP-1.mode.57 \
        output.DP-1.scale.2 \
        output.DP-1.hdr.disable \
        output.DP-1.wcg.disable
end
