function __bootstrap_display
    # Mode numbers describe one particular monitor pair, not all KDE desktops.
    if test "$BOOTSTRAP_DISPLAY_PROFILE" != s90d-denon; or not command -q kscreen-doctor
        echo 'This function requires BOOTSTRAP_DISPLAY_PROFILE=s90d-denon and kscreen-doctor.' >&2
        return 1
    end
end
