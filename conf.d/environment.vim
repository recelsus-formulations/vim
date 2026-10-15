function! s:has_environment(name) abort
    return !empty(getenv(a:name)) && getenv(a:name) isnot v:null
endfunction

function! s:detect() abort
    let environment = {
                \ 'is_windows': has('win32'), 'is_macos': has('macunix'),
                \ 'is_wsl': has('wsl') || s:has_environment('WSL_DISTRO_NAME') || s:has_environment('WSL_INTEROP'),
                \ 'is_tmux': s:has_environment('TMUX'),
                \ 'is_ssh': s:has_environment('SSH_CONNECTION') || s:has_environment('SSH_TTY'),
                \ 'has_wayland': s:has_environment('WAYLAND_DISPLAY'), 'has_x11': s:has_environment('DISPLAY'),
                \ 'paste_command': []}
    if environment.is_ssh
        return environment
    endif
    if environment.is_windows || environment.is_wsl
        if executable('win32yank.exe')
            let environment.paste_command = ['win32yank.exe', '-o', '--lf']
        else
            let candidates = environment.is_wsl ? ['powershell.exe', 'pwsh.exe']
                        \ : ['pwsh', 'powershell', 'powershell.exe']
            for command in candidates
                if executable(command)
                    let environment.paste_command = [command, '-NoLogo', '-NoProfile', '-NonInteractive',
                                \ '-Command', '[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); '
                                \ . '$ErrorActionPreference = ''Stop''; '
                                \ . '[Console]::Out.Write([string](Get-Clipboard -Raw))']
                    break
                endif
            endfor
        endif
    endif
    if empty(environment.paste_command)
        if environment.is_macos && executable('pbpaste')
            let environment.paste_command = ['pbpaste']
        elseif environment.has_wayland && executable('wl-paste')
            let environment.paste_command = ['wl-paste', '--no-newline']
        elseif environment.has_x11 && executable('xclip')
            let environment.paste_command = ['xclip', '-selection', 'clipboard', '-out']
        endif
    endif
    return environment
endfunction

let g:revim_environment = s:detect()
