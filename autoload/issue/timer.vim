
" vim-unite-issue - Issue tracker and timer for Vim
" Maintainer: Rafael Bodill <justrafi at gmail dot com>
" License: MIT license
"-------------------------------------------------

let s:save_cpo = &cpo
set cpo&vim

" Some defaults " {{{
let s:delim = '	'
" }}}

" Public methods
" --------------
function! issue#timer#start(repo, key) " {{{
	let pid = s:get_pid_path(a:repo, a:key)

	if filereadable(pid)
		throw 'Seems like issue has already been started'
	else
		" Write the PID file with timestamp
		call writefile([ localtime() ], pid)

		" Register issue in roster
		call s:register(a:repo, a:key, 1)
	endif
endfunction

" }}}
function! issue#timer#stop(repo, key) " {{{
	let pid = s:get_pid_path(a:repo, a:key)

	if filereadable(pid)
		" Read the PID file with timestamp
		let properties = readfile(pid)
		if len(properties) == 0
			throw 'Uh uh. The timer pid file is empty. Please report this!'
		endif

		" Calculate time spent and log into timesheet
		let time_started = properties[0]
		let time_stopped = localtime()
		let time_spent = time_stopped - time_started
		if delete(pid) == 0
			" Log the time into csv sheet
			call s:log_time(a:repo, a:key, time_spent)

			" Register issue in roster
			call s:register(a:repo, a:key, 0)

			" Show a nice informative message to the user
			echomsg printf('You''ve spent %s on %s, logged in local timesheet',
				\ s:print_time(time_spent),
				\ a:key)
		else
			throw 'Unable to delete pid file! Time was not stopped nor logged.'
		endif
	else
		throw 'Seems like issue hasn''t been started yet'
	endif
endfunction
" }}}

" Private methods
" ---------------
function! s:get_pid_path(repo, key) " {{{
	" Returns the unique PID file path for an issue
	"
	let uid = printf('%s/%s', a:repo, a:key)

	return g:unite_source_issue_data_dir.'/'
		\.'pid_'.issue#escape_filename(uid)
endfunction

" }}}
function! s:log_time(repo, key, seconds) " {{{
	" Logs time in timesheet for a specific issue
	"
	let timesheet = g:unite_source_issue_data_dir.'/timesheet.csv'

	if filereadable(timesheet)
		let log = readfile(timesheet)
	else
		let log = []
	endif

	let entry = printf(repeat('%s'.s:delim, 3).'%s',
		\ a:repo, a:key, localtime(), a:seconds)

	call add(log, entry)
	call writefile(log, timesheet)
endfunction

" }}}
function! s:register(repo, key, state) " {{{
	let roster = issue#roster()
	let entry = printf('%s/%s', a:repo, a:key)

	if a:state == 1
		call add(roster, entry)
	else
		call filter(roster, 'v:val != "'.entry.'"')
	endif

	return issue#roster(roster)
endfunction

" }}}
function! s:print_time(seconds) " {{{
	" Returns a human-readable time-lapse
	" Author: https://github.com/rainerborene/vim-timetap
	"
	let pp = []
	let hours = floor(a:seconds / 3600)
	let minutes = ceil(fmod(a:seconds, 3600) / 60)
	if hours > 0
		call add(pp, float2nr(hours))
		call add(pp, hours > 1 ? 'hours' : 'hour')
	endif
	if hours > 0 && minutes > 0
		call add(pp, 'and')
	endif
	if minutes > 0
		call add(pp, float2nr(minutes))
		call add(pp, minutes > 1 ? 'minutes' : 'minute')
	endif
	return join(pp)
endfunction
" }}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim: set ts=2 sw=2 tw=80 noet :
