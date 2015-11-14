
" vim-unite-issue - Issue tracker and timer for Vim
" Maintainer: Rafael Bodill <justrafi at gmail dot com>
" License: MIT license
"-------------------------------------------------

let s:save_cpo = &cpo
set cpo&vim

" Global default settings for JIRA's data {{{
if ! exists('g:unite_source_issue_jira_api_version')
	let g:unite_source_issue_jira_api_version = 2
endif

if ! exists('g:unite_source_issue_jira_limit')
	let g:unite_source_issue_jira_limit = 300
endif

if ! exists('g:unite_source_issue_jira_type_table')
	let g:unite_source_issue_jira_type_table = {
		\ 1: 'bug', 2: 'feature', 3: 'task', 4: 'sub',
		\ 5: 'epic', 6: 'story' }
endif

if ! exists('g:unite_source_issue_jira_status_table')
	let g:unite_source_issue_jira_status_table = {
		\ 0: 'open', 1: 'reopen', 2: 'resolved', 3: 'closed' }
endif

if ! exists('g:unite_source_issue_jira_priority_table')
	let g:unite_source_issue_jira_priority_table = {
		\ 10000: '•', 1: '!', 2: '+', 3: '-', 4: 'v', 5: '.' }
endif

" }}}
" Private JIRA Request header {{{
let s:jira_request_header = {
	\ 'User-Agent': 'unite-issue',
	\ 'Content-type': 'application/json',
	\ 'Authorization': 'Basic '.
	\   webapi#base64#b64encode(g:jira_username.':'.g:jira_password)
	\ }
" }}}

" Public methods
" --------------
function! issue#provider#jira#fetch_issues(arg, context, roster) " {{{
	" Queries JIRA's API issues, and parses candidates for Unite.
	"
	if ! exists('g:jira_url') || ! exists('g:jira_username')
		call unite#print_error('unite-issue requires `g:jira_url` and `g:jira_username` variables')
	endif

	" Use Unite's context object to look for a custom jql
	" argument, e.g. -custom-issue-jql=project=FOO\ AND\ assignee=joe
	let jql = get(a:context, 'custom_issue_jql', '')
	let response = s:fetch_issues(jql)
	return s:parse_issues(response.issues, a:roster)
endfunction

" }}}
function! issue#provider#jira#highlight() " {{{
	" Defines JIRA's issue number highlight.
	"
	" Match an upper-case word immediately followed by a dash and digits
	syntax match uniteSource__Issue_Key /\h[A-Z]\+\-\d\+\>/
				\ contained containedin=uniteSource__Issue
	highlight default link uniteSource__Issue_Key Constant
endfunction
" }}}

" Private methods
" ---------------
function! s:jira_query_url(jql, limit, fields) " {{{
	" Generates a proper JIRA API URL querying list of issues
	"
	let base = substitute(g:jira_url, '/\?$', '', '')
	let query = printf('jql=%s&maxResults=%s&fields=%s', a:jql, a:limit, a:fields)
	return printf('%s/rest/api/%s/search?%s',
			\ base, g:unite_source_issue_jira_api_version, query)
endfunction

" }}}
function! s:jira_issue_url(key) " {{{
	" Generates a proper JIRA API URL for issue fetching.
	"
	let base = substitute(g:jira_url, '/\?$', '', '')
	return printf('%s/rest/api/%s/issue/%s',
			\ base, g:unite_source_issue_jira_api_version, a:key)
endfunction

" }}}
function! s:fetch_issues(jql) " {{{
	" Queries JIRA's API with a custom JQL.
	"
	let jql = substitute(a:jql, " ", "+", "g")
	if len(jql) == 0
		let jql = printf('assignee=%s+AND+resolution=unresolved', g:jira_username)
	endif

	let fields = 'id,key,issuetype,parent,priority,summary,status,labels'
	let url = s:jira_query_url(jql, g:unite_source_issue_jira_limit, fields)
	let res = webapi#http#get(url, {}, s:jira_request_header)

	if res.status !~ '^2.*'
		return [ 'error', 'Failed to fetch JIRA issue list' ]
	endif

	return webapi#json#decode(res.content)
endfunction

" }}}
function! s:parse_issues(issues, roster) " {{{
	" Parses JIRA's issue list and prepares possible Unite candidates.
	"
	let candidates = []
	for issue in a:issues
		let priority = get(g:unite_source_issue_jira_priority_table,
			\ issue.fields.priority.id, issue.fields.priority.name)
		let status = get(g:unite_source_issue_jira_status_table,
			\ issue.fields.status.id, issue.fields.status.name)
		let type = get(g:unite_source_issue_jira_type_table,
			\ issue.fields.issuetype.id, issue.fields.issuetype.name)
		let started = index(a:roster, 'jira/'.issue.key) >= 0

		let word = printf('%-9s %-7s:%-9s %-9s | %s%s %s',
			\ started ? '▶ '.issue.key : issue.key,
			\ priority,
			\ (len(status) > 9 ? strpart(status, 0, 8) : status),
			\ type,
			\ has_key(issue.fields, 'parent') ? issue.fields.parent.key.' / ' : '',
			\ substitute(issue.fields.summary, '^\s\+', '', ''),
			\ len(issue.fields.labels) > 0 ? '['.join(issue.fields.labels, ', ').']' : ''
			\ )

		let item = {
			\ 'word': word,
			\ 'source': 'issue',
			\ 'source__issue_info' : {
			\   'repo': 'jira',
			\   'key': issue.key,
			\   'url': g:jira_url.'/browse/'.issue.key,
			\   'fetch_issue': function('s:fetch_issue'),
			\  }
			\ }

		call add(candidates, item)
	endfor

	return candidates
endfunction

" }}}
function! s:fetch_issue() dict " {{{
	" Queries JIRA API for a specific issue.
	"
	let url = s:jira_issue_url(self.key)
	let res = webapi#http#get(url, {}, s:jira_request_header)

	if res.status !~ '^2.*'
		return [ 'error', 'Failed to fetch JIRA issue' ]
	endif

	let payload = webapi#json#decode(res.content)
	return s:view_issue(payload)
endfunction

" }}}
function! s:view_issue(issue) " {{{
	" Returns a Markdown representation of issue dictionary.
	"
	let doc = printf('%s / %s / %s',
		\ a:issue.fields.project.name, a:issue.key, a:issue.fields.summary)
	let doc .= "\n===\n"
	let table = {
			\ 'Type': 'issuetype.name',
			\ 'Status': 'status.name',
			\ 'Priority': 'priority.name',
			\ 'Resolution': 'resolution.name',
			\ 'Resolution Date': 'resolutiondate',
			\ 'Assignee': 'assignee.name',
			\ }

	let i = 0
	let column_width = 30
	for [ title, path ] in items(table)
		let odd = i % 2 > 0
		let value = issue#get_path(a:issue.fields, path)
		let prop = '['.title.']: '.value
		if odd
			let prop = repeat(' ', column_width - strdisplaywidth(last_prop)).prop."\n"
		else
			let last_prop = prop
		endif
		let doc .= prop
		let i += 1
	endfor

	" Collect labels
	if len(a:issue.fields.labels) > 0
		let doc .= '[Labels]: '.join(a:issue.fields.labels, ', ')."\n"
	endif

	" Collect versions
	if len(a:issue.fields.versions) > 0
		let versions = []
		for aversion in a:issue.fields.versions
			call add(versions, aversion.name)
		endfor
		let doc .= '[Versions]: '.join(versions, ', ')."\n"
	endif

	" Display body of issue
	if len(a:issue.fields.description) > 0
		let doc .= "\nDescription\n-----------\n"
		let doc .= s:convert_to_markdown(a:issue.fields.description)."\n"
	endif

	" Collect comments
	if a:issue.fields.comment.total > 0
		let doc .= "\nComments\n--------\n"
		for comment in a:issue.fields.comment.comments
			let doc .= printf('_%s_: ', comment.author.name)
				\.s:convert_to_markdown(comment.body)."\n"
		endfor
	endif

	return doc
endfunction

" }}}
function! s:convert_to_markdown(txt) " {{{
	" Converts Atlassian JIRA markup to Markdown.
	"
	let txt = a:txt
	let txt = substitute(txt, 'h\(\d\+\)\. ', '\=repeat("#", submatch(1))." "', 'g')
	let txt = substitute(txt, '{code\(:\([a-z]\+\)\)\?}', '```\2', 'g')
	let txt = substitute(txt, '{{\([^}\n]\+\)}}', '`\1`', 'g')
	let txt = substitute(txt, '\*\([^\*\n]\{-}\)\*', '\*\*\1\*\*', 'g')
	let txt = substitute(txt, '_\([^_\n]\{-}\)_', '\*\1\*', 'g')
	let txt = substitute(txt, '\s\zs-\([^-\n]\{-}\)-', '~~~\1~~~', 'g')
	let txt = substitute(txt, '+\([^+\n]\+\)+', '<ins>\1</ins>', 'g')
	let txt = substitute(txt, '\^\([^\^\n]\+\)\^', '<sup>\1</sup>', 'g')
	let txt = substitute(txt, '??\([^?\n]\+\)??', '<cite>\1</cite>', 'g')
	let txt = substitute(txt, '\[\([^|\]\n]\+\)|\([^\]\n]\+\)\]', '[\1](\2)', 'g')
	let txt = substitute(txt, '\[\([\([^\]\n]\+\)\]\([^(]*\)', '<\1>\2', 'g')
	let txt = substitute(txt, "\r", '', 'g')
	return txt
endfunction

" }}}
function! s:convert_from_markdown(txt) " {{{
	" Converts Markdown to Atlassian JIRA markup.
	"
	" TODO: Will be used for writing comments.
	return a:txt
endfunction
" }}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim: set ts=2 sw=2 tw=80 noet :
