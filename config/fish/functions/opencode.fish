# opencode wrapper: auto-exports session to Obsidian on graceful exit.
# Usage is identical to plain `opencode` — all args pass through.
# The log-ses.py script only runs after a successful TUI exit (status 0).
function opencode --wraps /home/will/.local/bin/opencode
    # Subcommands that should NOT trigger auto-export on completion
    set _skip session export debug providers auth agent upgrade uninstall \
              serve web models stats import github pr mcp completion acp plugin plug db

    if contains "$argv[1]" $_skip
        command opencode $argv
    else
        # Interactive TUI launch — wrap with auto-export on graceful exit
        command opencode $argv
        if test $status -eq 0
            python3 ~/.opencode/bin/log-ses.py 2>/dev/null
        end
    end
end
