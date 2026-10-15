let s:root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let s:clipboard_script = filter(getscriptinfo(),
            \ 'v:val.name ==# s:root . "/conf.d/clipboard.vim"')[0]
let s:Encode = function('<SNR>' . s:clipboard_script.sid . '_encode')
call assert_equal('', s:Encode(''))
call assert_equal('Zg==', s:Encode('f'))
call assert_equal('Zm8=', s:Encode('fo'))
call assert_equal('Zm9v', s:Encode('foo'))
call assert_equal('5pel5pys6Kqe', s:Encode('日本語'), 'OSC52 encodes UTF-8 bytes')
call RevimClipboardCopy('+', 'V', ['alpha', 'beta'])
call assert_equal(['V', ['alpha', 'beta']], RevimClipboardPaste('+'))
execute 'source ' . fnameescape(s:root . '/conf.d/clipboard.vim')
call assert_equal(['V', ['alpha', 'beta']], RevimClipboardPaste('+'), 'Reloading settings preserves the cache')
call RevimClipboardCopy('*', "\<C-v>5", ['block'])
call assert_equal(["\<C-v>5", ['block']], RevimClipboardPaste('*'), 'Block register width is preserved')

let s:environment = deepcopy(g:revim_environment)
let s:external = get(g:, 'revim_clipboard_external_paste', 0)
try
    let g:revim_environment.paste_command = ['git', '--version']
    let g:revim_clipboard_external_paste = 0
    call assert_equal(['V', ['alpha', 'beta']], RevimClipboardPaste('+'), 'External paste is opt-in')
    if executable('git')
        " Git supplies harmless test output without reading the system clipboard.
        let g:revim_clipboard_external_paste = 1
        let s:result = RevimClipboardPaste('+')
        call assert_equal('V', s:result[0], 'A trailing newline creates a linewise register')
        call assert_match('^git version ', s:result[1][0])
        let g:revim_environment.paste_command = ['git', 'revim-invalid-command']
        call assert_equal(s:result, RevimClipboardPaste('+'), 'A failed command preserves cached content')
        let g:revim_environment.paste_command = [v:progpath, '-Nu', 'NONE', '-i', 'NONE', '-n', '-es',
                    \ '-c', 'sleep 5', '-c', 'qa!']
        let s:started = reltime()
        call assert_equal(s:result, RevimClipboardPaste('+'), 'A timeout preserves cached content')
        call assert_true(reltimefloat(reltime(s:started)) < 3.5, 'Clipboard commands time out after two seconds')
    endif
finally
    let g:revim_environment = s:environment
    let g:revim_clipboard_external_paste = 0
endtry

enew
call setline(1, 'copy me')
normal! yy
call assert_equal(['V', ['copy me']], RevimClipboardPaste('+'), 'Normal yank updates the OSC52 cache')
normal! p
call assert_equal(['copy me', 'copy me'], getline(1, '$'), 'Normal put uses the cached register')
call setreg('a', 'named register', 'v')
call feedkeys('"ap', 'xt')
call assert_match('named register', getline('.'), 'An explicit named register keeps native put behaviour')
enew!
let g:revim_clipboard_external_paste = s:external

let s:variables = ['PATH', 'WSL_DISTRO_NAME', 'WSL_INTEROP', 'SSH_CONNECTION', 'SSH_TTY', 'TMUX']
let s:values = {}
for s:variable in s:variables
    let s:values[s:variable] = getenv(s:variable)
endfor
let s:tools = tempname()
call mkdir(s:tools, 'p', 0700)
try
    call writefile([], s:tools . '/win32yank.exe')
    call setfperm(s:tools . '/win32yank.exe', 'rwx------')
    let $PATH = s:tools
    let $WSL_DISTRO_NAME = 'revim-test'
    let $WSL_INTEROP = ''
    let $SSH_CONNECTION = ''
    let $SSH_TTY = ''
    let $TMUX = 'revim-test'
    execute 'source ' . fnameescape(s:root . '/conf.d/environment.vim')
    call assert_true(g:revim_environment.is_wsl)
    call assert_true(g:revim_environment.is_tmux)
    call assert_equal(['win32yank.exe', '-o', '--lf'], g:revim_environment.paste_command)
    let $SSH_TTY = 'revim-test'
    execute 'source ' . fnameescape(s:root . '/conf.d/environment.vim')
    call assert_true(g:revim_environment.is_ssh)
    call assert_equal([], g:revim_environment.paste_command, 'SSH never selects a remote clipboard command')
finally
    for s:variable in s:variables
        call setenv(s:variable, s:values[s:variable])
    endfor
    call delete(s:tools, 'rf')
    let g:revim_environment = s:environment
endtry
