
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

if ! exists('g:unite_source_issue_jira_request_header')
	let g:unite_source_issue_jira_request_header = { }
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
		call unite#print_source_error(
			\ 'unite-issue requires `g:jira_url` and `g:jira_username` variables',
			\ 'issue')
	endif

	" Use Unite's context object to look for a custom jql
	" argument, e.g. -custom-issue-jql=project=FOO\ AND\ assignee=joe
	let jql = get(a:context, 'custom_issue_jql', '')
	if len(jql) == 0
		let jql = s:jira_build_jql({'assignee' : substitute(g:jira_username, '@', '\\\\u0040', ''), 'resolution': 'unresolved', 'project':  a:arg})
	endif

	call unite#print_source_message('Fetch JIRA: '.jql, 'issue')
	let response = s:fetch_issues(jql)
	if has_key(response, 'error')
		call unite#print_source_error('Error occured: '.response.error, 'issue')
	endif
	return s:parse_issues(response.issues, a:roster)
endfunction

" }}}
function! issue#provider#jira#highlight() " {{{
	" Defines JIRA's issue number highlight.

	" Match an upper-case word immediately followed by a dash and digits
	syntax match uniteSource__Issue_Key /\h[A-Z]\+\-\d\+\>/
				\ contained containedin=uniteSource__Issue
	highlight default link uniteSource__Issue_Key Constant
endfunction
" }}}

" Private methods
" ---------------
function! s:jira_build_jql(elements, ...) "{{{
	" Generates a proper jql string from multiple options
	"
	let link = a:0 > 0 ? a:000[0] : 'AND'
	let jql=''
	for key in keys(a:elements)
		let jql_part=''
		if type(a:elements[key]) == 4
			" If the element is a dictionary we want to group it
			let jql_part = '('.s:jira_build_jql(a:elements[key]['elements'], a:elements[key]['link']).')'
		elseif type(a:elements[key]) <=1
			" If the element is a number or string just print it
			if len(a:elements[key]) != 0
				let jql_part=printf('%s=%s',key,a:elements[key])
			endif
		elseif type(a:elements[key]) == 3
			" If we have a list we should group and OR it
			let jql_part = printf('(%s=%s)',key,join(a:elements[key],printf(' OR %s=', key)))
		endif
		" Insert link if neccessary
		if len(jql) != 0 && len(jql_part) != 0
			let jql=jql.' '.link.' '
		endif
		" Append current part if available
		if len(jql_part) != 0
			let jql=jql.jql_part
		endif
	endfor
	return substitute(jql, " ", "+","g")
endfunction

"	}}}
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
	let jql = a:jql
	let fields = 'id,key,issuetype,parent,priority,summary,status,labels,assignee'
	let url = s:jira_query_url(jql, g:unite_source_issue_jira_limit, fields)
	let headers = s:jira_request_header
	call extend(headers, g:unite_source_issue_jira_request_header)

	let res = webapi#http#get(url, {}, headers)

	if res.status !~ '^2.*'
		return { 'issues' : [], 'error': 'Failed to fetch JIRA issue list' }
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
		let assignee = ''

		if type(issue.fields.assignee) == type({}) &&
			\ has_key(issue.fields.assignee, 'displayName')
			let assignee = issue.fields.assignee.displayName
		endif

		" If the issue has been started, mark it.
		let iss = issue.key
		if index(a:roster, 'jira/'.issue.key) >= 0
			if &tenc == 'utf-8'
				let iss = '▶ ' . issue.key
			else
				let iss = '> ' . issue.key
			endif
		endif

		" Figure out the widths for the status and type
		let s_width = max(map(copy(g:unite_source_issue_jira_status_table),
			\ 'strlen(v:val)'))
		let t_width = max(map(copy(g:unite_source_issue_jira_type_table),
			\ 'strlen(v:val)'))

		" Get the amount of room for the ticket summary / labels
		let ww = winwidth(0) - s_width - t_width - 37
		if ww < 0
			let ww = 10
		endif

		" Truncate the description / labels according to ww
		let word = substitute(issue.fields.summary, '^\s\+', '', '')
		if has_key(issue.fields, 'labels') && len(issue.fields.labels) > 0
			let word .= '['.join(issue.fields.labels, ', ').']'
		endif
		let word = issue#str_trunc(word, ww)

		" Format the display line for unite
		let word = printf('%-12S %-3S:%-'
			\ . s_width . 'S %-' . t_width . 'S  %10S | %s',
			\ iss,
			\ issue#str_trunc(priority, 3),
			\ status,
			\ type,
			\ issue#str_trunc(assignee, 10),
			\ word)

		let item = {
			\ 'word': word,
			\ 'source': 'issue',
			\ 'source__issue_info': {
			\   'repo': 'jira',
			\   'key': issue.key,
			\   'url': g:jira_url.'/browse/'.issue.key,
			\   'fetch_issue': function('s:fetch_issue'),
			\   'add_comment': function('s:add_comment'),
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
	let headers = s:jira_request_header
	call extend(headers, g:unite_source_issue_jira_request_header)
	let res = webapi#http#get(url, {}, headers)

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
	let doc = printf('%s / %s', a:issue.key, a:issue.fields.summary)
	let doc .= "\n===\n\n"

	let table = {
			\ 'Type': 'issuetype.name',
			\ 'Status': 'status.name',
			\ 'Priority': 'priority.name',
			\ 'Resolution': 'resolution.name',
			\ 'Resolution Date': 'resolution.date',
			\ 'Assignee': 'assignee.displayName',
			\ }

	let i = 0
	let column_width = 30
	for [ title, path ] in items(table)
		let odd = i % 2 > 0
		let value = issue#get_path(a:issue.fields, path)
		if value != ''
			let prop = '['.title.']: '.value
			if odd
				let prop = repeat(' ', column_width - strdisplaywidth(last_prop)).prop."\n"
			else
				let last_prop = prop
			endif
			let doc .= prop
			let i += 1
		endif
	endfor

	" Add an additional newline if we only added an odd number of
	" fields.
	if i % 2 > 0
		let doc .= "\n"
	endif

	" Collect labels
	if has_key(a:issue.fields, 'labels') && len(a:issue.fields.labels) > 0
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
		let doc .= "\nDescription\n-----------\n\n"
		let doc .= s:convert_to_markdown(a:issue.fields.description)."\n"
	endif

	" Collect comments
	if a:issue.fields.comment.total > 0
		let doc .= "\nComments\n--------\n\n"
		for comment in a:issue.fields.comment.comments
			let doc .= printf('{{{ _%s_: ', comment.author.displayName)
				\.s:convert_to_markdown(comment.body)."\n}}}\n\n"
		endfor
	endif

	return doc
endfunction

" }}}
function! s:convert_to_markdown(txt) " {{{
	" Converts Atlassian JIRA markup to Markdown.
	"

	let i = 0
	let txt = ''

	" TODO: Preserve context in the {code} tag.
	for t in split(a:txt, '{code\(:\([a-z]\+\)\)\?}')
		if i % 2 > 0
			let t = substitute(t, '^[\r\n]\+', '', '')
			let t = substitute(t, '[\r\n\t ]\+$', '', '')
			let txt .= "```\n{{{ " . t . "\n}}}\n```\n"
		else
			let t = substitute(t, 'h\(\d\+\)\. ', '\=repeat("#", submatch(1))." "', 'g')
			let t = substitute(t, '{{\([^}\n]\+\)}}', '`\1`', 'g')
			let t = substitute(t, '\*\([^\*\n]\{-}\)\*', '\*\*\1\*\*', 'g')
			let t = substitute(t, '_\([^_\n]\{-}\)_', '\*\1\*', 'g')
			let t = substitute(t, '\s\zs-\([^-\n]\{-}\)-', '~~~\1~~~', 'g')
			let t = substitute(t, '+\([^+\n]\+\)+', '<ins>\1</ins>', 'g')
			let t = substitute(t, '\^\([^\^\n]\+\)\^', '<sup>\1</sup>', 'g')
			let t = substitute(t, '??\([^?\n]\+\)??', '<cite>\1</cite>', 'g')
			let t = substitute(t, '\[\([^|\]\n]\+\)|\([^\]\n]\+\)\]', '[\1](\2)', 'g')
			let t = substitute(t, '\[\([\([^\]\n]\+\)\]\([^(]*\)', '<\1>\2', 'g')
			let txt .= t
		endif

		let i += 1
	endfor

	let txt = substitute(txt, "\r", '', 'g')
	return txt
endfunction

" }}}
function! s:convert_from_markdown(txt) " {{{
	" Converts Markdown to Atlassian JIRA markup.
	"
	let i = 0
	let txt = ''

	let code_only = 0
	let lst = split(a:txt, '```\([a-z]\+\)\?')
	if len(lst) == 1 && match(a:txt, '```') > -1
		let code_only = 1
	endif

	for t in lst
		if i % 2 > 0 || code_only == 1
			let t = substitute(t, '{{{', '', 'g')
			let t = substitute(t, '}}}', '', 'g')
			let t = substitute(t, '^[\r\n\t ]\+', '', '')
			let t = substitute(t, '[\r\n\t ]\+$', '', '')
			let txt .= "{code}\n" . t . "\n{code}\n"
		else
			let t = substitute(t, '{{{', '', 'g')
			let t = substitute(t, '}}}', '', 'g')
			let t = substitute(t, '\(#\+\)',
				\ '\="h" . strlen(submatch(1)) . "."', 'g')
			let t = substitute(t, '`\([^}\n]\+\)`', '{{\1}}', 'g')
			let t = substitute(t, '[^\*]\*\*\([^_\n]\{-}\)\*[^\*]\*',
				\ '_\1_', 'g')
			let t = substitute(t, '\*\*\*\([^\n]\{-}\)\*\*\*', '\*\1\*', 'g')
			let t = substitute(t, '\~\~\~\([^-\n]\{-}\)\~\~\~', '-\1-', 'g')
			let t = substitute(t, '<ins>\([^+\n]\+\)</ins>', '+\1+', 'g')
			let t = substitute(t, '<sup>\([^\^\n]\+\)</sup>', '^\1^', 'g')
			let t = substitute(t, '<cite>\([^?\n]\+\)</cite>', '??\1??', 'g')
			let t = substitute(t, '\[\([^|\]\n]\+\)\](\([^\]\n]\+\))',
				\ '[\1|\2]', 'g')
			let txt .= t
		endif

		let i += 1
	endfor

	let txt = substitute(txt, "\r", '', 'g')
	return txt
endfunction

" }}}
function! s:add_comment(txt) dict " {{{
	" Add a comment

	if a:txt == ''
		return
	endif

	let j = webapi#json#encode({
		\ 'body': s:convert_from_markdown(a:txt)
	\ })
	let res = webapi#http#post(
		\ s:jira_issue_url(self.key) . '/comment',
		\ j, s:jira_request_header)
	if res.status !~ '^2.*'
		echoerr 'failed to post comment (' . res.status . ')'
	endif
endfunction
" }}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim: set ts=2 sw=2 tw=80 noet :
