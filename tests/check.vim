set nomore
let s:root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let s:temporary = tempname()
call mkdir(s:temporary, 'p')
execute 'cd ' . fnameescape(s:temporary)

function! s:wait_until(predicate) abort
    let started = reltime()
    while !call(a:predicate, []) && reltimefloat(reltime(started)) < 8.0
        sleep 20m
    endwhile
    return call(a:predicate, [])
endfunction

function! s:git(arguments) abort
    let job = job_start(['git', '-C', s:temporary] + a:arguments,
                \ {'in_io': 'null', 'out_io': 'null', 'err_io': 'null'})
    call assert_true(s:wait_until({-> job_status(job) !=# 'run'}), 'Git fixture command completes')
    call assert_equal(0, get(job_info(job), 'exitval', -1), 'Git fixture command succeeds')
endfunction

function! s:signs() abort
    return sign_getplaced(bufnr('%'), {'group': 'revim_git'})[0].signs
endfunction

try
    call assert_equal(2, &shiftwidth)
    call assert_true(&expandtab)
    call assert_false(&loadplugins)
    call assert_equal(' ', g:mapleader)
    call assert_true(isdirectory(substitute(&undodir, '//$', '', '')))

    execute 'source ' . fnameescape(s:root . '/tests/clipboard.vim')

    enew
    call feedkeys("i(\<Esc>", 'xt')
    call assert_equal('()', getline(1), 'Opening bracket creates a pair')
    call setline(1, '')
    call feedkeys("i()\<Esc>", 'xt')
    call assert_equal('()', getline(1), 'Closing bracket skips an existing closer')
    call setline(1, '')
    call feedkeys("i(\<BS>\<Esc>", 'xt')
    call assert_equal('', getline(1), 'Backspace removes an empty pair')
    call feedkeys("i'\<Esc>", 'xt')
    call assert_equal("''", getline(1), 'Quote creates a pair')
    call setline(1, '')
    call feedkeys("iword'\<Esc>", 'xt')
    call assert_equal("word'", getline(1), 'A quote after a word remains literal')
    call setline(1, 'text')
    call feedkeys("0i(\<Esc>", 'xt')
    call assert_equal('(text', getline(1), 'Opening before text remains literal')
    set paste
    call setline(1, '')
    call feedkeys("i(\<Esc>", 'xt')
    call assert_equal('(', getline(1), 'Paste mode leaves input unchanged')
    set nopaste

    call setline(1, 'one two three two')
    normal! 0
    call feedkeys('2ft', 'xt')
    call assert_equal(9, col('.'), 'Counted native character motion remains available')
    call feedkeys(';', 'xt')
    call assert_equal(15, col('.'), 'Native character motion repeat remains available')
    doautocmd CursorMoved
    call assert_equal([], getmatches(), 'Temporary scope highlights are cleared')
    normal! 0
    call feedkeys('dft', 'xt')
    call assert_equal('wo three two', getline(1), 'Operator-pending character motion remains available')

    call setline(1, 'one two three')
    normal! 0
    call feedkeys("\<C-f>a", 'xt')
    call assert_equal(5, col('.'), 'A label jumps to the nearest visible word')
    normal! ``
    call assert_equal(1, col('.'), 'The previous-context mark returns to the origin')
    call feedkeys("\<C-f>\<Esc>", 'xt')
    call assert_equal(1, col('.'), 'Cancelling a jump keeps the original position')

    call writefile(['alpha Needle', 'needle second'], 'a file.txt')
    call writefile(['Needle hidden'], '.hidden')
    call mkdir('node_modules')
    call writefile(['Needle excluded'], 'node_modules/skip.txt')
    call writefile(["Needle\nNUL"], 'binary')
    call mkdir('directory')
    call writefile(['inside'], 'directory/nested.txt')
    Find needle
    call assert_true(s:wait_until({-> getqflist({'title': 1}).title =~# '\[complete'}), 'Search completes')
    call assert_equal(3, len(getqflist()), 'Search includes hidden files and skips excluded or binary files')
    call assert_equal([1, 1, 2], map(getqflist(), 'v:val.lnum'))
    Find Needle
    call assert_true(s:wait_until({-> getqflist({'title': 1}).title =~# '\[complete'}))
    call assert_equal(2, len(getqflist()), 'Smart case distinguishes uppercase patterns')
    Find Needle\c
    call assert_true(s:wait_until({-> getqflist({'title': 1}).title =~# '\[complete'}))
    call assert_equal(3, len(getqflist()), 'Explicit case override remains available')
    let previous = getqflist({'id': 0}).id
    Find \(
    call assert_equal(previous, getqflist({'id': 0}).id, 'Invalid regex preserves the previous results')
    cclose
    silent! %bwipeout!

    Ex
    call assert_equal('nofile', &buftype)
    call assert_equal(1, b:ex_tree)
    let entry = index(map(copy(b:ex_tree_entries), 'fnamemodify(v:val.path, ":t")'), 'a file.txt')
    call cursor(entry + 1, 1)
    call feedkeys("\<Tab>", 'xt')
    call assert_equal(1, b:ex_tree, 'Preview returns focus to the tree')
    let preview = bufnr(s:temporary . '/a file.txt')
    call assert_true(preview > 0, 'Preview opens the selected file')
    call assert_equal('unload', getbufvar(preview, '&bufhidden'))
    call feedkeys("\<CR>", 'xt')
    call assert_equal('a file.txt', expand('%:t'), 'Return opens the file')
    call assert_equal('', &bufhidden, 'Opening promotes the preview buffer')
    Ex
    Ex
    let entry = index(map(copy(b:ex_tree_entries), 'fnamemodify(v:val.path, ":t")'), 'a file.txt')
    call cursor(entry + 1, 1)
    call feedkeys("r\<C-u>renamed file.txt\<CR>", 'xt')
    call assert_true(filereadable('renamed file.txt'), 'Rename updates the filesystem')
    call assert_false(filereadable('a file.txt'))
    call assert_equal('renamed file.txt', fnamemodify(bufname(preview), ':t'), 'Rename updates open buffers')
    let entry = index(map(copy(b:ex_tree_entries), 'fnamemodify(v:val.path, ":t")'), 'renamed file.txt')
    call cursor(entry + 1, 1)
    call feedkeys("r\<C-u>.hidden\<CR>", 'xt')
    call assert_true(filereadable('renamed file.txt'), 'Rename refuses an existing destination')
    call setbufvar(preview, '&modified', 1)
    call feedkeys('d', 'xt')
    call assert_true(filereadable('renamed file.txt'), 'Deletion refuses an unsaved buffer')
    call setbufvar(preview, '&modified', 0)
    call feedkeys("aadded.txt\<CR>", 'xt')
    call assert_true(filereadable('added.txt'), 'Create adds a new file')
    let entry = index(map(copy(b:ex_tree_entries), 'fnamemodify(v:val.path, ":t")'), 'renamed file.txt')
    call cursor(entry + 1, 1)
    call feedkeys("r\<C-u>a file.txt\<CR>", 'xt')
    Ex
    Ex
    let entry = index(map(copy(b:ex_tree_entries), 'fnamemodify(v:val.path, ":t")'), 'directory')
    call cursor(entry + 1, 1)
    call feedkeys("\<CR>", 'xt')
    call assert_true(index(map(copy(b:ex_tree_entries), 'fnamemodify(v:val.path, ":t")'), 'nested.txt') >= 0,
                \ 'Return expands a directory')
    call feedkeys("q", 'xt')
    silent! %bwipeout!

    execute 'source ' . fnameescape(s:root . '/tests/tree.vim')

    if has('job') && executable('git')
        call s:git(['init', '-q'])
        call writefile(['one', 'two', 'three'], 'tracked [1].txt')
        call s:git(['add', '--', 'tracked [1].txt'])
        edit tracked\ [1].txt
        call assert_true(s:wait_until({-> empty(s:signs())}), 'Clean index has no signs')
        call setline(2, 'changed')
        doautocmd TextChanged
        call assert_true(s:wait_until({-> !empty(s:signs())}), 'Unsaved edits produce Git signs')
        call assert_equal('ExGitChange', s:signs()[0].name)
        call assert_equal(2, s:signs()[0].lnum)
        call append(3, 'four')
        doautocmd TextChanged
        call assert_true(s:wait_until({-> len(s:signs()) == 2}), 'Added line produces a second sign')
        call assert_equal('ExGitAdd', s:signs()[1].name)
        write
        call s:git(['add', '--', 'tracked [1].txt'])
        call assert_true(s:wait_until({-> empty(s:signs())}), 'External staging clears the signs')
        silent 1delete _
        doautocmd TextChanged
        call assert_true(s:wait_until({-> !empty(s:signs())}), 'Deleting the first line produces a sign')
        call assert_equal('ExGitTopDelete', s:signs()[0].name)
        call assert_equal(1, s:signs()[0].lnum)
        edit!
        call writefile([''], 'blank.txt')
        call s:git(['add', '--', 'blank.txt'])
        edit blank.txt
        sleep 250m
        call assert_equal([], s:signs(), 'A single newline is distinct from an empty file')
        edit a\ file.txt
        call setline(1, 'untracked edit')
        doautocmd TextChanged
        sleep 250m
        call assert_equal([], s:signs(), 'Untracked files receive no signs')
    endif

    if has('terminal')
        enew!
        let origin = win_getid()
        ToggleTerm
        let s:terminal = bufnr('%')
        call assert_equal('terminal', &buftype)
        call assert_match('running', term_getstatus(s:terminal))
        call assert_notmatch('normal', term_getstatus(s:terminal), 'A new terminal accepts shell input')
        call feedkeys("\<C-\>\<C-n>", 'nx')
        call assert_match('normal', term_getstatus(s:terminal), 'Terminal normal mode can be entered explicitly')
        ToggleTerm
        call assert_equal(origin, win_getid(), 'Hiding the terminal restores the origin')
        call assert_match('running', term_getstatus(s:terminal), 'Hidden terminal keeps its process')
        ToggleTerm
        call assert_equal(s:terminal, bufnr('%'), 'Showing the terminal reuses its process')
        call assert_notmatch('normal', term_getstatus(s:terminal), 'Showing a terminal resumes shell input')
        resize 4
        ToggleTerm
        tabnew
        let other_origin = win_getid()
        ToggleTerm
        call assert_equal(s:terminal, bufnr('%'), 'Tabs share the terminal process')
        resize 6
        ToggleTerm
        call assert_equal(other_origin, win_getid(), 'Each tab retains its own terminal origin')
        tabclose
        ToggleTerm
        call assert_equal(4, winheight(0), 'Terminal heights are independent between tabs')
        ToggleTerm
        call assert_equal(origin, win_getid())
        ToggleTerm float
        let s:second = bufnr('%')
        call assert_notequal(s:terminal, s:second, 'The second terminal has an independent process')
        call assert_notmatch('normal', term_getstatus(s:second), 'The second terminal starts in shell input mode')
        call feedkeys("\<C-\>\<C-n>", 'nx')
        ToggleTerm float
        ToggleTerm float
        call assert_equal(s:second, bufnr('%'))
        call assert_notmatch('normal', term_getstatus(s:second), 'The second terminal also resumes shell input')
        ToggleTerm float
        call term_sendkeys(s:terminal, "exit\<CR>")
        call term_sendkeys(s:second, "exit\<CR>")
        call assert_true(s:wait_until({-> !bufexists(s:terminal) || term_getstatus(s:terminal) !~# 'running'}))
    endif
catch
    call add(v:errors, v:exception . ' at ' . v:throwpoint)
finally
    FindCancel
    execute 'cd ' . fnameescape(s:root)
    call delete(s:temporary, 'rf')
endtry

if !empty(v:errors)
    for s:error in v:errors
        echomsg s:error
    endfor
    cquit
endif
qa!
