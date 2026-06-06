function d --description "Send directory to existing Dolphin instance"
    set target $PWD
    if test (count $argv) -gt 0
        set target (realpath $argv[1])
    end
    
    # Execute, suppress Qt warnings, background, and detach
    nohup dolphin $target >/dev/null 2>&1 &
    disown
end
