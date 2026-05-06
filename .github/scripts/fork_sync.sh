#!/usr/bin/env bash

. <(curl -fsSL "$BASH_LIB") || exit 1

msg_add() {
  local -n list_ref=$2 msg_ref=$3
  local msg_title=$1 msg_str item

  ((${#list_ref[@]})) || return 0

  printf -v msg_str '\n<b>%s（ %d ）：</b>' "$msg_title" "${#list_ref[@]}"
  msg_ref+=$msg_str

  for item in "${list_ref[@]}"; do
    msg_ref+=$'\n'"• <code>$item</code>"
  done
}

main() {
  local succ_list hard_list fail_list conf_raw conf_list conf_row user_name tok_key \
    tok_val repo_raw repo_list repo_item repo_path repo_br res_stat msg_body

  lib::need_f "$CONF_FILE"
  succ_list=() hard_list=() fail_list=()
  printf '%s\n' '### 🔄 同步汇总' '| 仓库 | 状态 |' '| :--- | :--- |' >>"$GITHUB_STEP_SUMMARY"

  mapfile -t conf_raw <"$CONF_FILE"
  lib::tidy conf_raw conf_list

  for conf_row in "${conf_list[@]}"; do
    user_name=${conf_row%:*}
    tok_key=${conf_row#*:}
    tok_val=${!tok_key}

    [[ $tok_val ]] || {
      lib::log_err "密钥缺失：$tok_key"
      continue
    }

    lib::log_inf "处理用户：$user_name"
    repo_raw=$(gh repo list "$user_name" -L 1000 --fork --json nameWithOwner,defaultBranchRef \
      -q '.[] | "\(.nameWithOwner):\(.defaultBranchRef.name)"' | sort -f)

    [[ $repo_raw ]] || {
      lib::log_wrn "无 Fork 仓库：$user_name"
      continue
    }

    mapfile -t repo_list <<<"$repo_raw"
    for repo_item in "${repo_list[@]}"; do
      repo_path=${repo_item%:*}
      repo_br=${repo_item#*:}

      lib::log_inf "开始同步：$repo_path [ $repo_br ]"

      if GH_TOKEN=$tok_val gh repo sync "$repo_path" -b "$repo_br"; then
        res_stat='✅ 成功'
        succ_list+=("$repo_item")
      elif GH_TOKEN=$tok_val gh repo sync "$repo_path" -b "$repo_br" --force; then
        res_stat='🔥 强制'
        hard_list+=("$repo_item")
      else
        res_stat='❌ 失败'
        fail_list+=("$repo_item")
      fi

      printf '| %s | %s |\n' "$repo_item" "$res_stat"
    done
  done >>"$GITHUB_STEP_SUMMARY"

  [[ $F_NTFY == true ]] || ((${#hard_list[@]} || ${#fail_list[@]})) || return 0

  msg_add '✅ 成功' succ_list msg_body
  msg_add '🔥 强制' hard_list msg_body
  msg_add '❌ 失败' fail_list msg_body

  printf '%s\n' 'msg<<EOF' "$msg_body" 'EOF' >>"$GITHUB_OUTPUT"
}

main "$@"
