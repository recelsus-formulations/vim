let s:search = get(s:, 'search', {})

function! s:cancel() abort
    if !empty(s:search)
        call timer_stop(get(s:search, 'timer', -1))
    endif
    let s:search = {}
endfunction

function! s:publish(done) abort
    let title = 'Find: ' . s:search.pattern . ' [' . (a:done ? 'complete' : 'searching')
                \ . ', skipped ' . s:search.skipped . (len(s:search.items) >= 500 ? ', limit 500' : '') . ']'
    call setqflist([], 'r', {'id': s:search.id, 'items': s:search.items, 'title': title})
    redraw
endfunction

function! s:step(timer) abort
    if empty(s:search) || s:search.timer != a:timer
        return
    endif
    let started = reltime()
    try
        while !empty(s:search.pending) && len(s:search.items) < 500
            let path = remove(s:search.pending, -1)
            let type = getftype(path)
            if type ==# 'dir'
                if index(['.git', '.cache', 'Library', 'node_modules'], fnamemodify(path, ':t')) >= 0
                    continue
                endif
                try
                    for name in reverse(sort(readdir(path)))
                        call add(s:search.pending, path . '/' . name)
                    endfor
                catch
                    let s:search.skipped += 1
                endtry
            elseif type ==# 'file' && filereadable(path) && getfsize(path) <= 1048576
                try
                    let lines = readfile(path, 'b')
                    " readfile() represents embedded NUL bytes as newlines.
                    if !empty(filter(copy(lines), 'stridx(v:val, "\n") >= 0'))
                        let s:search.skipped += 1
                        continue
                    endif
                    for index in range(len(lines))
                        let column = match(lines[index], s:search.regex)
                        if column >= 0
                            call add(s:search.items, {'filename': path, 'lnum': index + 1,
                                        \ 'col': column + 1, 'text': lines[index]})
                            if len(s:search.items) >= 500
                                break
                            endif
                        endif
                    endfor
                catch
                    let s:search.skipped += 1
                endtry
            else
                let s:search.skipped += 1
            endif
            if reltimefloat(reltime(started)) > 0.012
                break
            endif
        endwhile
        let done = empty(s:search.pending) || len(s:search.items) >= 500
        call s:publish(done)
        if done
            call timer_stop(a:timer)
            let s:search.timer = -1
        endif
    catch
        call s:cancel()
        echo 'revim: search stopped: ' . v:exception
    endtry
endfunction

function! s:find(pattern) abort
    let pattern = a:pattern
    if empty(pattern)
        let pattern = input('Find (Vim regex): ')
    endif
    if empty(pattern)
        return
    endif
    let regex = (pattern =~# '[A-Z]' ? '\C' : '\c') . pattern
    try
        call match('', regex)
    catch
        echo 'revim: invalid pattern: ' . v:exception
        return
    endtry
    call s:cancel()
    call setqflist([], ' ', {'title': 'Find: ' . pattern, 'items': []})
    let s:search = {'pattern': pattern, 'regex': regex, 'pending': [getcwd()],
                \ 'items': [], 'skipped': 0, 'id': getqflist({'id': 0}).id, 'timer': -1}
    botright copen
    let s:search.timer = timer_start(15, function('<SID>step'), {'repeat': -1})
endfunction

command! -nargs=* Find call <SID>find(<q-args>)
command! FindCancel call <SID>cancel()
nnoremap <silent> <leader>fg :Find<CR>
augroup revim_find
    autocmd!
    autocmd VimLeavePre * call <SID>cancel()
augroup END
