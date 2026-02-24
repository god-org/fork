#!/bin/bash

set -euo pipefail

if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "❌ 要求 Bash 版本 ≥ 4.0，当前版本：${BASH_VERSION}。" >&2
  exit 127
fi

function log() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ✅：${*}。"
}

# shellcheck disable=SC2329
function error() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ❌：${*}。" >&2
}

function add_msg_block() {
  local icon title arr_ref block_header repo
  declare -n arr_ref="${3}"

  icon="${1}"
  title="${2}"

  [[ "${#arr_ref[@]}" -eq 0 ]] && return

  printf -v block_header "\n<b>%s %s ( %d ):</b>" "${icon}" "${title}" "${#arr_ref[@]}"
  tg_msg_body="${tg_msg_body}${block_header}"

  for repo in "${arr_ref[@]}"; do
    tg_msg_body="${tg_msg_body}\n• <code>${repo}</code>"
  done
}

function main() {
  local temp_resp owners success_repos skipped_repos failed_repos
  local user current_gh_token row repo_name branch
  local response_code status_icon status_msg error_msg
  local tg_msg_body

  temp_resp="$(mktemp)"
  chmod 0600 "${temp_resp}"
  # shellcheck disable=SC2064
  trap "rm -f '${temp_resp}'" EXIT

  owners=('zzzzzzqqq8' 'dog-org')

  {
    echo "### 🔄 同步任务汇总"
    echo "| 仓库 | 分支 | 状态 | 详情 |"
    echo "| :--- | :--- | :--- | :--- |"
  } >>"${GITHUB_STEP_SUMMARY}"

  success_repos=()
  skipped_repos=()
  failed_repos=()

  for user in "${owners[@]}"; do
    log "正在处理用户：${user}"

    case "${user}" in
    'zzzzzzqqq8') current_gh_token="${ZZQ_TOKEN:-}" ;;
    'dog-org') current_gh_token="${DOG_TOKEN:-}" ;;
    *) continue ;;
    esac

    while read -r row || [[ -n "${row}" ]]; do
      [[ -z "${row}" ]] && continue

      repo_name="${row%,*}"
      branch="${row#*,}"

      log "正在同步：${repo_name} [ ${branch} ]"

      response_code=$(curl -sSL -o "${temp_resp}" -w "%{http_code}" \
        -X POST \
        -H "Authorization: Bearer ${current_gh_token}" \
        "https://api.github.com/repos/${repo_name}/merge-upstream" \
        -d "{\"branch\":\"${branch}\"}")

      case "${response_code}" in
      200 | 202)
        status_icon='✅ 成功'
        status_msg='同步成功'
        success_repos+=("${repo_name}")
        ;;
      409)
        status_icon='⚠️ 跳过'
        status_msg='已是最新'
        skipped_repos+=("${repo_name}")
        ;;
      *)
        status_icon='❌ 失败'
        error_msg=$(jq -r '.message' "${temp_resp}" 2>/dev/null || echo "HTTP ${response_code}")
        status_msg="${error_msg}"
        failed_repos+=("${repo_name} (${error_msg})")
        ;;
      esac

      echo "| ${repo_name} | ${branch} | ${status_icon} | ${status_msg} |" >>"${GITHUB_STEP_SUMMARY}"

    done < <(gh repo list "${user}" --fork --limit 1000 --json nameWithOwner,defaultBranchRef --jq '.[] | "\(.nameWithOwner),\(.defaultBranchRef.name)"' | sort -f)
  done

  tg_msg_body=''
  add_msg_block '✅' '成功' success_repos
  add_msg_block '⚠️' '跳过' skipped_repos
  add_msg_block '❌' '失败' failed_repos

  [[ -z "${tg_msg_body}" ]] && tg_msg_body="\n<b>⚠️ 本次无同步任务执行</b>"

  {
    echo "TG_MSG<<EOF"
    printf "%b\n" "${tg_msg_body}"
    echo "EOF"
  } >>"${GITHUB_ENV}"
}

main "$@"

unset -f log error add_msg_block main
