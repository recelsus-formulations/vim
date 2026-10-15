let s:running = get(s:, 'running', {})
let s:debounce = get(s:, 'debounce', -1)
let s:poll = get(s:, 'poll', -1)
let s:git = ['git', '--no-optional-locks', '--no-pager', '--literal-pathspecs', '-c', 'core.fsmonitor=false']

function! s:clear(buffer) abort
    call sign_unplace('revim_git', {'buffer': a:buffer})
endfunction

function! s:dispose(state) abort
    call delete(a:state.directory, 'rf')
    if has_key(s:running, a:state.buffer)
        call remove(s:running, a:state.buffer)
    endif
endfunction

function! s:is_current(state) abort
    return bufexists(a:state.buffer)
                \ && getbufvar(a:state.buffer, 'changedtick') == a:state.tick
                \ && fnamemodify(bufname(a:state.buffer), ':p') ==# a:state.path
endfunction

function! s:place(state, lines) abort
    call s:clear(a:state.buffer)
    let id = 1
    let last = len(getbufline(a:state.buffer, 1, '$'))
    for text in a:lines
        let hunk = matchlist(text, '^@@ -\(\d\+\)\%(,\(\d\+\)\)\? +\(\d\+\)\%(,\(\d\+\)\)\? @@')
        if empty(hunk)
            continue
        endif
        let old_count = empty(hunk[2]) ? 1 : str2nr(hunk[2])
        let start = str2nr(hunk[3])
        let new_count = empty(hunk[4]) ? 1 : str2nr(hunk[4])
        if new_count == 0
            let name = start == 0 ? 'ExGitTopDelete' : 'ExGitDelete'
            call sign_place(id, 'revim_git', name, a:state.buffer,
                        \ {'lnum': min([last, max([1, start])]), 'priority': 10})
            let id += 1
        else
            for offset in range(new_count)
                let name = offset >= old_count ? 'ExGitAdd' : 'ExGitChange'
                if old_count > new_count && offset == new_count - 1
                    let name = 'ExGitChangeDelete'
                endif
                call sign_place(id, 'revim_git', name, a:state.buffer,
                            \ {'lnum': min([last, start + offset]), 'priority': 10})
                let id += 1
            endfor
        endif
    endfor
endfunction

function! s:start_job(state, command, stage) abort
    let a:state.stage = a:stage
    let a:state.job = job_start(a:command, {'cwd': fnamemodify(a:state.path, ':h'),
                \ 'in_io': 'null', 'out_io': 'file', 'out_name': a:state.directory . '/output',
                \ 'err_io': 'null', 'exit_cb': function('<SID>finished', [a:state])})
    if job_status(a:state.job) ==# 'fail'
        call s:clear(a:state.buffer)
        call s:dispose(a:state)
    endif
endfunction

function! s:finished(state, job, status) abort
    if !s:is_current(a:state)
        call s:dispose(a:state)
        return
    endif
    try
        let output = a:state.directory . '/output'
        if (a:state.stage !=# 'diff' && a:status != 0) || a:status > 1
            call s:clear(a:state.buffer)
            call s:dispose(a:state)
            return
        endif
        if a:state.stage ==# 'tracked'
            let metadata = readfile(output, 'b')
            let entry = matchlist(get(metadata, 0, ''), '^100\d\{3} \([0-9a-f]\+\) 0\t')
            if len(metadata) != 1 || empty(entry)
                call s:clear(a:state.buffer)
                call s:dispose(a:state)
                return
            endif
            call s:start_job(a:state, s:git + ['cat-file', 'blob', entry[1]], 'index')
            return
        elseif a:state.stage ==# 'index'
            if getfsize(output) > 1048576
                call s:clear(a:state.buffer)
                call s:dispose(a:state)
                return
            endif
            let lines = readfile(output, 'b')
            if !empty(filter(copy(lines), 'stridx(v:val, "\n") >= 0'))
                call s:clear(a:state.buffer)
                call s:dispose(a:state)
                return
            endif
            call rename(output, a:state.directory . '/index')
            call s:start_job(a:state, s:git + ['diff', '--no-index', '--no-ext-diff', '--no-textconv',
                        \ '--no-color', '--unified=0', '--', a:state.directory . '/index',
                        \ a:state.directory . '/buffer'], 'diff')
            return
        else
            call s:place(a:state, readfile(output))
        endif
    catch
        call s:clear(a:state.buffer)
    endtry
    call s:dispose(a:state)
endfunction

function! s:update(buffer, window) abort
    if has_key(s:running, a:buffer) || !bufloaded(a:buffer)
        return
    endif
    let path = fnamemodify(bufname(a:buffer), ':p')
    if getbufvar(a:buffer, '&buftype') !=# '' || getftype(path) !=# 'file'
                \ || path =~# '[\r\n]' || getbufvar(a:buffer, '&binary')
                \ || index(['', 'utf-8'], getbufvar(a:buffer, '&fileencoding')) < 0
        call s:clear(a:buffer)
        return
    endif
    let lines = getbufline(a:buffer, 1, '$')
    let size = 0
    for text in lines
        let size += strlen(text) + 1
        if stridx(text, "\n") >= 0
            call s:clear(a:buffer)
            return
        endif
    endfor
    if size > 1048576 || len(lines) > 20000
        call s:clear(a:buffer)
        return
    endif
    let directory = tempname()
    call mkdir(directory, 'p', 0700)
    let state = {'buffer': a:buffer, 'path': path, 'directory': directory,
                \ 'tick': getbufvar(a:buffer, 'changedtick')}
    let s:running[a:buffer] = state
    let saved = copy(lines)
    if getbufvar(a:buffer, '&fileformat') ==# 'dos'
        call map(saved, 'v:val . "\r"')
    endif
    let is_empty = len(saved) == 1 && saved[0] ==# ''
                \ && str2nr(win_execute(a:window, 'echo line2byte(2)')) < 0
    if getbufvar(a:buffer, '&endofline') && !is_empty
        call add(saved, '')
    endif
    if getbufvar(a:buffer, '&bomb') && getbufvar(a:buffer, '&fileencoding') =~# '^\%(utf-8\)\?$'
        let saved[0] = nr2char(0xfeff) . saved[0]
    endif
    call writefile(saved, directory . '/buffer', 'b')
    call s:start_job(state, s:git + ['ls-files', '--stage', '-z', '--',
                \ fnamemodify(path, ':t')], 'tracked')
endfunction

function! s:visible(timer) abort
    let seen = {}
    for window in getwininfo()
        if !has_key(seen, window.bufnr)
            let seen[window.bufnr] = 1
            call s:update(window.bufnr, window.winid)
        endif
    endfor
endfunction

function! s:changed() abort
    call timer_stop(s:debounce)
    let s:debounce = timer_start(150, function('<SID>visible'))
endfunction

function! s:stop() abort
    call timer_stop(s:poll)
    call timer_stop(s:debounce)
    for state in values(copy(s:running))
        if has_key(state, 'job')
            call job_stop(state.job)
        endif
        call s:dispose(state)
    endfor
endfunction

function! s:colours() abort
    highlight default ExGitAdd ctermfg=114 guifg=#98c379
    highlight default ExGitChange ctermfg=180 guifg=#e5c07b
    highlight default ExGitDelete ctermfg=203 guifg=#e06c75
endfunction

if has('job') && has('timers') && exists('*sign_place') && executable('git')
    call s:colours()
    call sign_define('ExGitAdd', {'text': '+', 'texthl': 'ExGitAdd', 'numhl': 'ExGitAdd'})
    call sign_define('ExGitChange', {'text': '|', 'texthl': 'ExGitChange', 'numhl': 'ExGitChange'})
    call sign_define('ExGitDelete', {'text': '_', 'texthl': 'ExGitDelete', 'numhl': 'ExGitDelete'})
    call sign_define('ExGitTopDelete', {'text': '-', 'texthl': 'ExGitDelete', 'numhl': 'ExGitDelete'})
    call sign_define('ExGitChangeDelete', {'text': '~', 'texthl': 'ExGitChange', 'numhl': 'ExGitChange'})
    call timer_stop(s:poll)
    let s:poll = timer_start(1000, function('<SID>visible'), {'repeat': -1})
    augroup revim_signs
        autocmd!
        autocmd BufEnter,BufWritePost,TextChanged,TextChangedI,FocusGained * call <SID>changed()
        autocmd ColorScheme * call <SID>colours()
        autocmd VimLeavePre * call <SID>stop()
    augroup END
endif
