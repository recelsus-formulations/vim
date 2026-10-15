function! s:select(name, key) abort
    let index = index(map(copy(b:ex_tree_entries), 'fnamemodify(v:val.path, ":t")'), a:name)
    call assert_true(index >= 0, 'The selected file is present in the tree')
    call cursor(index + 1, 1)
    call feedkeys(a:key, 'xt')
endfunction

function! s:tree_window() abort
    let windows = filter(getwininfo(), 'v:val.tabnr == tabpagenr() && getbufvar(v:val.bufnr, "ex_tree", 0)')
    return empty(windows) ? 0 : windows[0].winid
endfunction

function! s:assert_layout() abort
    call assert_equal(2, winnr('$'), 'Only the tree and the requested file are displayed')
    call assert_equal(30, getwininfo(s:tree_window())[0].width, 'Reopening a file restores the tree width')
    let windows = filter(getwininfo(), 'v:val.tabnr == tabpagenr() && !getbufvar(v:val.bufnr, "ex_tree", 0)')
    call assert_equal(1, len(windows))
    if !empty(windows)
        let window = windows[0].winid
        call assert_true(getwinvar(window, '&number'), 'Editing windows retain line numbers')
        call assert_equal('yes', getwinvar(window, '&signcolumn'), 'Editing windows retain the sign column')
        call assert_false(getwinvar(window, '&winfixwidth'), 'Editing windows do not inherit tree width fixing')
        call assert_false(empty(bufname(windows[0].bufnr)), 'No empty window is left behind')
    endif
endfunction

tabnew
Ex
let s:tree = win_getid()
call s:select('a file.txt', "\<CR>")
call s:assert_layout()
for s:key in ["\<CR>", "\<C-v>", "\<C-x>", "\<Tab>"]
    " The remaining tree naturally expands to full width when the editing window closes.
    call win_gotoid(filter(getwininfo(),
                \ 'v:val.tabnr == tabpagenr() && !getbufvar(v:val.bufnr, "ex_tree", 0)')[0].winid)
    close
    call assert_equal(1, winnr('$'))
    call assert_equal(s:tree, win_getid())
    call s:select('.hidden', s:key)
    call s:assert_layout()
    if s:key ==# "\<Tab>"
        call assert_equal(s:tree, win_getid(), 'Preview leaves focus in the tree')
    endif
endfor

call win_gotoid(filter(getwininfo(),
            \ 'v:val.tabnr == tabpagenr() && !getbufvar(v:val.bufnr, "ex_tree", 0)')[0].winid)
bdelete
call win_gotoid(s:tree_window())
call s:select('a file.txt', "\<C-v>")
call s:assert_layout()

let s:editing = win_getid()
vsplit
let s:windows = winnr('$')
call win_gotoid(s:tree_window())
let s:statuses = map(filter(getwininfo(), 'v:val.tabnr == tabpagenr()'),
            \ '[v:val.winid, getwinvar(v:val.winid, "&statusline")]')
call feedkeys("\<Esc>", 't')
call s:select('.hidden', "\<C-v>")
call assert_equal(s:windows, winnr('$'), 'Cancelling target selection does not create a split')
for s:item in s:statuses
    call assert_equal(s:item[1], getwinvar(s:item[0], '&statusline'), 'Target labels are removed after cancellation')
endfor
call win_gotoid(s:editing)
close
call win_gotoid(s:tree_window())

let s:cwd = getcwd()
execute 'edit ' . fnameescape(s:cwd . '/directory')
sleep 100m
call assert_equal(fnamemodify(s:cwd . '/directory', ':p:h'), t:ex_tree_root)
call assert_equal(s:cwd, getcwd(), 'Opening a directory does not change the working directory')
call assert_equal(2, winnr('$'), 'Opening a directory in the tree reuses its existing window')
call assert_equal(s:tree_window(), win_getid())
execute 'edit ' . fnameescape(s:cwd)
sleep 100m
call assert_equal(s:cwd, t:ex_tree_root)
call assert_equal(2, winnr('$'))

if has('terminal')
    ToggleTerm
    call assert_false(&number, 'Terminals do not show editing line numbers')
    call assert_false(&winfixwidth, 'Terminals do not inherit tree width fixing')
    let s:terminal = bufnr('%')
    ToggleTerm
    call assert_equal(s:tree_window(), win_getid())
    call term_sendkeys(s:terminal, "exit\<CR>")
endif
tabclose!

tabnew
call setline(1, 'unsaved content')
let s:unsaved = bufnr('%')
let s:cwd = getcwd()
execute 'edit ' . fnameescape(s:cwd . '/directory')
sleep 100m
call assert_equal(2, winnr('$'), 'A directory argument creates one tree beside the existing editor')
call assert_equal(['unsaved content'], getbufline(s:unsaved, 1, '$'), 'Opening a directory preserves unsaved text')
call assert_true(getbufvar(s:unsaved, '&modified'))
call assert_true(index(tabpagebuflist(), s:unsaved) >= 0, 'The unsaved editor remains displayed')
call win_gotoid(win_findbuf(s:unsaved)[0])
execute 'split ' . fnameescape(s:cwd)
sleep 100m
call assert_equal(1, len(filter(getwininfo(),
            \ 'v:val.tabnr == tabpagenr() && getbufvar(v:val.bufnr, "ex_tree", 0)')),
            \ 'Splitting a directory reuses the existing tree')
call assert_equal(s:cwd, t:ex_tree_root)
call assert_true(getbufvar(s:unsaved, '&modified'))
tabclose!
