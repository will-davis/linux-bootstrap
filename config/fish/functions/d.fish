function d --description "Send directory to existing Dolphin instance"
    command -q dolphin; or return 127
    set target $PWD
    if test (count $argv) -gt 0
        set target (realpath $argv[1])
    end
    
    # Execute, suppress Qt warnings, background, and detach
    nohup dolphin $target >/dev/null 2>&1 &
    disown
end
