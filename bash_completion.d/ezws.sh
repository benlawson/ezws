_ezws()
{
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="connect startup sftp stop bind add sshfs list reindex"

    case "${prev}" in
        connect|startup|sftp|stop|bind|sshfs)
            local hostname=""
            COMPREPLY=( $(compgen -W "${hostname}" ${cur}) )
            return 0
            ;;
        *)
            ;;
    esac

	COMPREPLY=( $(compgen -W "${opts}" ${cur}) )
	return 0
}
complete -F _ezws ezws.sh

