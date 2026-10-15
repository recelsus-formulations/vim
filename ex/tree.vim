function! s:collect(path, depth, entries, lines) abort
    let names = sort(readdir(a:path))
    let names = filter(copy(names), 'isdirectory(a:path . "/" . v:val)')
                \ + filter(copy(names), '!isdirectory(a:path . "/" . v:val)')
    for name in names
        let path = simplify(a:path . '/' . name)
        let directory = isdirectory(path)
        let expanded = directory && get(t:ex_tree_expanded, path, 0) && getftype(path) !=# 'link'
        call add(a:entries, {'path': path, 'directory': directory, 'depth': a:depth})
        call add(a:lines, repeat('  ', a:depth) . (directory ? (expanded ? '- ' : '+ ') : '  ')
                    \ . strtrans(name) . (directory ? '/' : ''))
        if expanded
            try
                call s:collect(path, a:depth + 1, a:entries, a:lines)
            catch
                " Unreadable directories remain visible but are not expanded.
            endtry
        endif
    endfor
endfunction

function! s:refresh() abort
    let position = getpos('.')
    let entries = [{'path': t:ex_tree_root, 'directory': 1, 'depth': -1}]
    let lines = [strtrans(t:ex_tree_root)]
    call s:collect(t:ex_tree_root, 0, entries, lines)
    let b:ex_tree_entries = entries
    setlocal modifiable
    call setline(1, lines)
    if line('$') > len(lines)
        execute (len(lines) + 1) . ',$delete _'
    endif
    setlocal nomodifiable nomodified
    call setpos('.', position)
endfunction

let s:tree_width = 30

function! s:resize(window) abort
    if win_id2tabwin(a:window)[0] == tabpagenr() && winnr('$') > 1
        call win_execute(a:window, 'vertical resize ' . max([1, min([s:tree_width, &columns - 22])]))
    endif
endfunction

function! s:target() abort
    let windows = filter(getwininfo(), 'v:val.tabnr == tabpagenr() && !v:val.quickfix'
                \ . ' && getbufvar(v:val.bufnr, "&buftype") ==# ""'
                \ . ' && !isdirectory(bufname(v:val.bufnr))'
                \ . ' && !getwinvar(v:val.winid, "&winfixbuf", 0)')
    if empty(windows)
        rightbelow vnew
        call RevimRestoreWindow()
        return {'window': win_getid(), 'created': 1}
    endif
    if len(windows) == 1
        return {'window': windows[0].winid, 'created': 0}
    endif
    let labels = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890'
    if len(windows) > strlen(labels)
        echo 'revim: too many windows to select'
        return {}
    endif
    let saved = []
    let laststatus = &laststatus
    try
        set laststatus=2
        for index in range(min([len(windows), strlen(labels)]))
            let window = windows[index].winid
            call add(saved, [window, getwinvar(window, '&statusline')])
            call setwinvar(window, '&statusline', ' [' . labels[index] . '] %f')
        endfor
        redraw
        let key = toupper(getcharstr())
        let index = stridx(labels, key)
        return strlen(key) == 1 && index >= 0 && index < len(saved)
                    \ ? {'window': saved[index][0], 'created': 0} : {}
    finally
        for item in saved
            call setwinvar(item[0], '&statusline', item[1])
        endfor
        let &laststatus = laststatus
    endtry
endfunction

function! s:open(mode) abort
    let entry = get(b:ex_tree_entries, line('.') - 1, {})
    if empty(entry)
        return
    endif
    if entry.directory
        if line('.') > 1 && getftype(entry.path) !=# 'link'
            let t:ex_tree_expanded[entry.path] = !get(t:ex_tree_expanded, entry.path, 0)
            call s:refresh()
        endif
        return
    endif
    let origin = win_getid()
    for window in getwininfo()
        if window.tabnr == tabpagenr() && fnamemodify(bufname(window.bufnr), ':p') ==# entry.path
                    \ && getbufvar(window.bufnr, '&buftype') ==# ''
            call win_gotoid(window.winid)
            if a:mode !=# 'preview'
                setlocal bufhidden=
            else
                call win_gotoid(origin)
            endif
            call s:resize(origin)
            return
        endif
    endfor
    let target = s:target()
    if empty(target)
        return
    endif
    call win_gotoid(target.window)
    let was_loaded = bufloaded(entry.path)
    let is_placeholder = empty(bufname('%')) && !&modified && line('$') == 1 && getline(1) ==# ''
    let command = 'edit'
    if !target.created && !is_placeholder
        if a:mode ==# 'vertical' || ((!&hidden && &modified) && index(['edit', 'preview'], a:mode) >= 0)
            let command = 'rightbelow vsplit'
        elseif a:mode ==# 'horizontal'
            let command = 'rightbelow split'
        endif
    endif
    try
        execute command . ' ' . fnameescape(entry.path)
        if a:mode ==# 'preview'
            if !was_loaded
                setlocal bufhidden=unload
                let b:ex_tree_preview = 1
            endif
        else
            setlocal bufhidden=
        endif
    catch
        echo 'revim: ' . v:exception
        call win_gotoid(origin)
    finally
        call s:resize(origin)
        if a:mode ==# 'preview'
            call win_gotoid(origin)
        endif
    endtry
endfunction

function! s:affected_buffers(path) abort
    return filter(getbufinfo(), 'fnamemodify(v:val.name, ":p") ==# a:path'
                \ . ' || stridx(fnamemodify(v:val.name, ":p"), a:path . "/") == 0')
endfunction

function! s:create() abort
    let entry = b:ex_tree_entries[line('.') - 1]
    let parent = entry.directory ? entry.path : fnamemodify(entry.path, ':h')
    let name = input('Create (trailing / for directory): ', '', 'file')
    if empty(name)
        return
    endif
    let path = simplify(parent . '/' . name)
    if !empty(getftype(path))
        echo 'revim: destination already exists'
        return
    endif
    try
        if name =~# '/$'
            call mkdir(path, 'p')
        elseif writefile([], path) != 0
            echo 'revim: could not create file'
        endif
    catch
        echo 'revim: ' . v:exception
    endtry
    call s:refresh()
endfunction

function! s:delete() abort
    if line('.') == 1
        return
    endif
    let path = b:ex_tree_entries[line('.') - 1].path
    let buffers = s:affected_buffers(path)
    if !empty(filter(copy(buffers), 'v:val.changed'))
        echo 'revim: deletion refused: unsaved buffer'
        return
    endif
    if confirm('Delete ' . strtrans(path) . ' and its contents?', "&Yes\n&No", 2) != 1
        return
    endif
    let flags = isdirectory(path) && getftype(path) !=# 'link' ? 'rf' : ''
    if delete(path, flags) != 0
        echo 'revim: deletion failed'
        return
    endif
    for buffer in buffers
        execute 'silent! bdelete ' . buffer.bufnr
    endfor
    call s:refresh()
endfunction

function! s:rename_buffer(buffer, destination) abort
    execute 'noautocmd keepalt buffer ' . a:buffer
    let old_name = expand('%:p')
    execute 'silent noautocmd keepalt file ' . fnameescape(a:destination)
    " :file creates an unloaded alternate buffer for the previous name.
    let alternate = bufnr(old_name)
    if alternate >= 0 && alternate != a:buffer && !buflisted(alternate) && !bufloaded(alternate)
        execute 'noautocmd bwipeout ' . alternate
    endif
endfunction

function! s:rename() abort
    if line('.') == 1
        return
    endif
    let path = b:ex_tree_entries[line('.') - 1].path
    let name = input('Rename to: ', fnamemodify(path, ':t'))
    if empty(name)
        return
    endif
    let destination = simplify(fnamemodify(path, ':h') . '/' . name)
    if path ==# destination
        return
    endif
    let buffers = s:affected_buffers(path)
    if !empty(getftype(destination)) || bufnr(destination) >= 0
        echo 'revim: destination already exists or has a buffer'
        return
    endif
    for buffer in buffers
        let new_name = destination . strpart(fnamemodify(buffer.name, ':p'), strlen(path))
        if bufnr(new_name) >= 0
            echo 'revim: destination buffer conflict'
            return
        endif
    endfor
    let tree_buffer = bufnr('%')
    setlocal bufhidden=hide
    try
        for buffer in buffers
            call s:rename_buffer(buffer.bufnr, destination
                        \ . strpart(fnamemodify(buffer.name, ':p'), strlen(path)))
        endfor
    finally
        execute 'noautocmd keepalt buffer ' . tree_buffer
        setlocal bufhidden=hide
    endtry
    if rename(path, destination) != 0
        setlocal bufhidden=hide
        try
            for buffer in buffers
                call s:rename_buffer(buffer.bufnr, buffer.name)
            endfor
        finally
            execute 'noautocmd keepalt buffer ' . tree_buffer
            setlocal bufhidden=hide
        endtry
        echo 'revim: rename failed'
        return
    endif
    let t:ex_tree_expanded = {}
    call s:refresh()
endfunction

function! s:close() abort
    if winnr('$') == 1
        rightbelow vnew
        call RevimRestoreWindow()
        wincmd p
    endif
    close
endfunction

function! s:show() abort
    if !exists('t:ex_tree_root')
        let t:ex_tree_root = fnamemodify(getcwd(), ':p')
        if t:ex_tree_root !=# '/'
            let t:ex_tree_root = substitute(t:ex_tree_root, '/$', '', '')
        endif
        let t:ex_tree_expanded = {}
    endif
    if bufexists(get(t:, 'ex_tree_buffer', -1))
        for window in getwininfo()
            if window.tabnr == tabpagenr() && window.bufnr == t:ex_tree_buffer
                call win_gotoid(window.winid)
                let t:ex_tree_window = window.winid
                call s:refresh()
                call s:resize(window.winid)
                return
            endif
        endfor
        execute 'topleft ' . s:tree_width . 'vsplit'
        execute 'buffer ' . t:ex_tree_buffer
    else
        execute 'topleft ' . s:tree_width . 'vnew'
    endif
    let b:ex_tree = 1
    let t:ex_tree_buffer = bufnr('%')
    let t:ex_tree_window = win_getid()
    call RevimSpecialWindow()
    setlocal buftype=nofile bufhidden=hide nobuflisted noswapfile winfixwidth filetype=revim_tree
    nnoremap <silent><buffer> <CR> :call <SID>open('edit')<CR>
    nnoremap <silent><buffer> <Tab> :call <SID>open('preview')<CR>
    nnoremap <silent><buffer> <C-v> :call <SID>open('vertical')<CR>
    nnoremap <silent><buffer> <C-x> :call <SID>open('horizontal')<CR>
    nnoremap <silent><buffer> a :call <SID>create()<CR>
    nnoremap <silent><buffer> d :call <SID>delete()<CR>
    nnoremap <silent><buffer> r :call <SID>rename()<CR>
    nnoremap <silent><buffer> R :call <SID>refresh()<CR>
    nnoremap <silent><buffer> q :call <SID>close()<CR>
    call s:refresh()
endfunction

function! s:toggle() abort
    for window in getwininfo()
        if window.tabnr == tabpagenr() && getbufvar(window.bufnr, 'ex_tree', 0)
            call win_gotoid(window.winid)
            call s:close()
            return
        endif
    endfor
    call s:show()
endfunction

function! s:directory(buffer, window, timer) abort
    if !bufexists(a:buffer) || win_id2tabwin(a:window)[0] != tabpagenr()
                \ || winbufnr(a:window) != a:buffer || getbufvar(a:buffer, '&modified')
        return
    endif
    let path = fnamemodify(bufname(a:buffer), ':p')
    if !isdirectory(path)
        return
    endif
    let origin = win_getid()
    call win_gotoid(a:window)
    let t:ex_tree_root = path ==# '/' ? path : substitute(path, '/$', '', '')
    let t:ex_tree_expanded = {}
    if get(t:, 'ex_tree_window', -1) == a:window && bufexists(get(t:, 'ex_tree_buffer', -1))
        execute 'buffer ' . t:ex_tree_buffer
        call s:refresh()
    else
        let previous = bufnr('#')
        if previous > 0 && getbufvar(previous, '&buftype') ==# '' && !isdirectory(bufname(previous))
            execute 'buffer ' . previous
        else
            enew
        endif
        call RevimRestoreWindow()
        call s:show()
    endif
    if empty(win_findbuf(a:buffer))
        execute 'silent bwipeout ' . a:buffer
    endif
    if origin != a:window
        call win_gotoid(origin)
    endif
endfunction

function! s:cleanup(timer) abort
    let buffers = map(gettabinfo(), 'get(v:val.variables, "ex_tree_buffer", -1)')
    for buffer in getbufinfo()
        if get(buffer.variables, 'ex_tree', 0) && index(buffers, buffer.bufnr) < 0
                    \ && empty(buffer.windows)
            execute 'silent bwipeout ' . buffer.bufnr
        endif
    endfor
endfunction

command! Ex call <SID>toggle()
nnoremap <silent> <C-e> :Ex<CR>
let g:loaded_netrw = 1
let g:loaded_netrwPlugin = 1
augroup revim_tree
    autocmd!
    autocmd BufEnter * if isdirectory(expand('%:p')) |
                \ call timer_start(0, function('<SID>directory', [bufnr('%'), win_getid()])) | endif
    autocmd TabClosed * call timer_start(0, function('<SID>cleanup'))
    autocmd TextChanged,TextChangedI * if get(b:, 'ex_tree_preview', 0) |
                \ setlocal bufhidden= | unlet b:ex_tree_preview | endif
augroup END
