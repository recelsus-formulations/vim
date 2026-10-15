let s:buffers = get(s:, 'buffers', {})

function! s:toggle(kind) abort
    if !has('terminal')
        echo 'revim: this Vim was built without +terminal'
        return
    endif
    if index(['horizontal', 'float'], a:kind) < 0
        echo 'Usage: ToggleTerm [horizontal|float]'
        return
    endif
    if !exists('t:ex_term_views')
        let t:ex_term_views = {}
    endif
    if !has_key(t:ex_term_views, a:kind)
        let t:ex_term_views[a:kind] = {}
    endif
    let view = t:ex_term_views[a:kind]
    let buffer = get(s:buffers, a:kind, -1)
    for window in getwininfo()
        if window.tabnr == tabpagenr() && window.bufnr == buffer
            let view.height = window.height
            if tabpagewinnr(tabpagenr(), '$') == 1
                botright new
                call RevimRestoreWindow()
            endif
            call win_execute(window.winid, 'hide')
            let origin = get(view, 'origin', 0)
            if win_id2tabwin(origin)[0] == tabpagenr()
                call win_gotoid(origin)
            endif
            return
        endif
    endfor
    let view.origin = win_getid()
    let height = get(view, 'height', max([1, float2nr(&lines * 0.3)]))
    execute 'botright ' . min([height, max([1, &lines - 6])]) . 'new'
    if bufexists(buffer) && term_getstatus(buffer) =~# 'running'
        execute 'buffer ' . buffer
    else
        " A list starts the configured shell directly, without an intermediary shell.
        let buffer = term_start([&shell], {'curwin': 1, 'term_finish': 'close'})
        if buffer <= 0
            close
            echo 'revim: could not start the configured shell'
            return
        endif
        let s:buffers[a:kind] = buffer
        setlocal bufhidden=hide nobuflisted
    endif
    call RevimSpecialWindow()
    if term_getstatus(buffer) =~# '\<normal\>'
        " :startinsert does not leave Vim's Terminal-Normal mode.
        normal! i
    endif
endfunction

command! -nargs=? ToggleTerm call <SID>toggle(empty(<q-args>) ? 'horizontal' : <q-args>)
nnoremap <silent> <C-t> :ToggleTerm<CR>
inoremap <silent> <C-t> <Esc>:ToggleTerm<CR>
nnoremap <silent> <leader>tf :ToggleTerm float<CR>
if has('terminal')
    tnoremap <silent> <C-t> <C-\><C-n>:ToggleTerm<CR>
    tnoremap <Esc> <C-\><C-n>
endif
