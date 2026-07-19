#!/bin/sh
# Shared helpers. Expect ROOT to be set by the caller.

# Apply unset keys from .github/ci.env into the current shell.
# Existing environment values win.
ci_load_env() {
	_env_file="${ROOT}/.github/ci.env"
	if [ ! -f "${_env_file}" ]; then
		echo "missing ${_env_file}" >&2
		return 1
	fi
	while IFS= read -r _line || [ -n "${_line}" ]; do
		case "${_line}" in
		'' | \#*) continue ;;
		esac
		_line=${_line%%#*}
		while [ "${_line#"${_line%%[![:space:]]*}"}" != "${_line}" ]; do
			_line=${_line#"${_line%%[![:space:]]*}"}
		done
		while [ "${_line%"${_line##*[![:space:]]}"}" != "${_line}" ]; do
			_line=${_line%"${_line##*[![:space:]]}"}
		done
		[ -z "${_line}" ] && continue
		case "${_line}" in
		*=*) ;;
		*) continue ;;
		esac
		_key=${_line%%=*}
		_val=${_line#*=}
		while [ "${_key%"${_key##*[![:space:]]}"}" != "${_key}" ]; do
			_key=${_key%"${_key##*[![:space:]]}"}
		done
		while [ "${_val#"${_val%%[![:space:]]*}"}" != "${_val}" ]; do
			_val=${_val#"${_val%%[![:space:]]*}"}
		done
		eval "_isset=\${${_key}+yes}"
		if [ -z "${_isset}" ]; then
			export "${_key}=${_val}"
		fi
		eval "_cur=\${${_key}}"
		if [ -n "${GITHUB_ENV:-}" ]; then
			printf '%s=%s\n' "${_key}" "${_cur}" >>"${GITHUB_ENV}"
		fi
		if [ "${CI_LOAD_ENV_PRINT:-0}" = "1" ]; then
			printf '%s=%s\n' "${_key}" "${_cur}"
		fi
	done <"${_env_file}"
	unset _env_file _line _key _val _isset _cur
}
