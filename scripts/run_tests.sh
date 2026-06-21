#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
plenary_dir="${PLENARY_DIR:-"${root_dir}/.deps/plenary.nvim"}"

if [[ ! -d "${plenary_dir}" ]]; then
	mkdir -p "$(dirname -- "${plenary_dir}")"
	git clone --depth 1 --filter=blob:none https://github.com/nvim-lua/plenary.nvim.git "${plenary_dir}"
elif [[ ! -d "${plenary_dir}/lua/plenary" ]]; then
	printf 'PLENARY_DIR does not look like plenary.nvim: %s\n' "${plenary_dir}" >&2
	exit 1
fi

export PLENARY_DIR="${plenary_dir}"
cd "${root_dir}"

use_color=0
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
	use_color=1
fi

if [[ "${use_color}" -eq 1 ]]; then
	color_reset=$'\033[0m'
	color_bold=$'\033[1m'
	color_dim=$'\033[2m'
	color_green=$'\033[32m'
	color_red=$'\033[31m'
	color_cyan=$'\033[36m'
else
	color_reset=''
	color_bold=''
	color_dim=''
	color_green=''
	color_red=''
	color_cyan=''
fi

if [[ "$#" -eq 0 ]]; then
	started_at="${SECONDS}"
	spec_files=(tests/*_spec.lua)
	scheduled="${#spec_files[@]}"

	set +e
	output="$(nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests" 2>&1)"
	status="$?"
	set -e

	success=0
	failed=0
	errors=0
	file_names=()
	file_passed=()
	file_failed=()
	file_errored=()
	current_file_index=-1

	trim_whitespace() {
		local value="${1}"
		value="${value#"${value%%[![:space:]]*}"}"
		value="${value%"${value##*[![:space:]]}"}"
		printf '%s' "${value}"
	}

	relative_path() {
		local path="${1}"
		if [[ "${path}" == "${root_dir}/"* ]]; then
			printf '%s' "${path#"${root_dir}/"}"
		else
			printf '%s' "${path}"
		fi
	}

	append_file_if_needed() {
		local raw_path
		raw_path="$(trim_whitespace "${1}")"
		if [[ -z "${raw_path}" ]]; then
			return
		fi
		current_file_index="${#file_names[@]}"
		file_names+=("${raw_path}")
		file_passed+=(0)
		file_failed+=(0)
		file_errored+=(0)
	}

	while IFS= read -r line; do
		if [[ "${line}" == *"Testing:"* ]]; then
			append_file_if_needed "${line#*Testing:}"
		elif [[ "${line}" == *"Success:"* && "${line}" =~ ([0-9]+)[[:space:]]*$ ]]; then
			success=$((success + BASH_REMATCH[1]))
			if [[ "${current_file_index}" -ge 0 ]]; then
				file_passed[${current_file_index}]="${BASH_REMATCH[1]}"
			fi
		elif [[ "${line}" == *"Failed :"* && "${line}" =~ ([0-9]+)[[:space:]]*$ ]]; then
			failed=$((failed + BASH_REMATCH[1]))
			if [[ "${current_file_index}" -ge 0 ]]; then
				file_failed[${current_file_index}]="${BASH_REMATCH[1]}"
			fi
		elif [[ "${line}" == *"Errors :"* && "${line}" =~ ([0-9]+)[[:space:]]*$ ]]; then
			errors=$((errors + BASH_REMATCH[1]))
			if [[ "${current_file_index}" -ge 0 ]]; then
				file_errored[${current_file_index}]="${BASH_REMATCH[1]}"
			fi
		fi
	done <<< "${output}"

	total_cases=$((success + failed + errors))
	pass_rate=0
	if [[ "${total_cases}" -gt 0 ]]; then
		pass_rate=$(((100 * success) / total_cases))
	fi

	duration_seconds=$((SECONDS - started_at))
	result_label="PASS"
	result_color="${color_green}"
	if [[ "${status}" -ne 0 ]]; then
		result_label="FAIL"
		result_color="${color_red}"
	fi

	if [[ "${status}" -ne 0 ]]; then
		printf '%s\n' "${output}"
		printf '\n'
	fi

	printf '%s========================================%s\n' "${color_dim}" "${color_reset}"
	printf '%s%sdoubt.nvim Test Suite%s\n' "${color_bold}" "${color_cyan}" "${color_reset}"
	printf '%s========================================%s\n' "${color_dim}" "${color_reset}"
	printf 'Result      : %s%s%s\n' "${result_color}" "${result_label}" "${color_reset}"
	printf 'Duration    : %ss\n' "${duration_seconds}"
	printf 'Spec Files  : %d\n' "${scheduled}"
	printf 'Test Cases  : %d\n' "${total_cases}"
	printf 'Passed      : %s%d%s\n' "${color_green}" "${success}" "${color_reset}"
	printf 'Failed      : %s%d%s\n' "${color_red}" "${failed}" "${color_reset}"
	printf 'Errors      : %s%d%s\n' "${color_red}" "${errors}" "${color_reset}"
	printf 'Pass Rate   : %d%%\n' "${pass_rate}"
	printf '%s----------------------------------------%s\n' "${color_dim}" "${color_reset}"
	printf '%sFile Overview%s\n' "${color_cyan}" "${color_reset}"

	for index in "${!file_names[@]}"; do
		status_tag="PASS"
		status_cell=" PASS "
		status_color="${color_green}"
		if [[ "${file_errored[index]}" -gt 0 ]]; then
			status_tag="ERROR"
			status_cell="ERROR "
			status_color="${color_red}"
		elif [[ "${file_failed[index]}" -gt 0 ]]; then
			status_tag="FAIL"
			status_cell=" FAIL "
			status_color="${color_red}"
		fi

		file_label="$(relative_path "${file_names[index]}")"
		printf '  [%s%s%s] %s (p:%s%d%s f:%s%d%s e:%s%d%s)\n' \
			"${status_color}" \
			"${status_cell}" \
			"${color_reset}" \
			"${file_label}" \
			"${color_green}" \
			"${file_passed[index]}" \
			"${color_reset}" \
			"${color_red}" \
			"${file_failed[index]}" \
			"${color_reset}" \
			"${color_red}" \
			"${file_errored[index]}" \
			"${color_reset}"
	done

	printf '%s========================================%s\n' "${color_dim}" "${color_reset}"
	exit "${status}"
fi

files=("$@")

for file in "${files[@]}"; do
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedFile ${file}"
done
