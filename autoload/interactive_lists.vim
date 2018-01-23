fu! s:capture(cmd) abort "{{{1
    if a:cmd ==# 'args'
        let list = argv()
        call map(list, { i,v -> {
        \                         'filename': v,
        \                         'text': fnamemodify(v, ':t'),
        \                       } })

    elseif a:cmd ==# 'changes'
        let list = s:capture_cmd_local_to_window('changes', '\v^%(\s+\d+){3}')

    elseif a:cmd ==# 'ls'
        let list = range(1, bufnr('$'))

    elseif a:cmd ==# 'marks'
        let list = s:capture_cmd_local_to_window('marks', '\v^\s+\S+%(\s+\d+){2}')

    elseif a:cmd ==# 'number'
        let pos = getpos('.')
        let list = split(execute('keepj '.getcmdline(), ''), '\n')
        call setpos('.', pos)

    elseif a:cmd ==# 'oldfiles'
        let list = split(execute('old'), '\n')

    elseif a:cmd ==# 'registers'
        let list = [ '"', '+', '-', '*', '/', '=' ]
        call extend(list, map(range(48,57)+range(97,122), { i,v -> nr2char(v,1) }))
    endif
    return list
endfu

fu! s:capture_cmd_local_to_window(cmd, pat) abort "{{{1
    " The changelist  is local  to a  window.
    " If we  are in a  location window,  `g:c` will show  us the changes  in the
    " latter.   But, we  are NOT  interested in  them. We want  the ones  in the
    " associated window. Same thing for the local marks.
    if &buftype ==# 'quickfix'
        noautocmd call lg#window#qf_open('loc')
        let list = split(execute(a:cmd), '\n')
        noautocmd wincmd p
    else
        let list = split(execute(a:cmd), '\n')
    endif
    return filter(list, { i,v -> v =~ a:pat })
endfu

fu! s:convert(output, cmd, bang) abort "{{{1
    if a:cmd ==# 'ls'
        call filter(a:output, a:bang ? { i,v -> bufexists(v) } : { i,v -> buflisted(v) })
        " Why is the first character in `printf()` a no-break space?{{{
        "
        " Because, by default, Vim reduces all leading spaces in the text to a single space.
        " We don't want that. We want them to be left as is, so that the buffer numbers are
        " right aligned in their field. So, we prefix the text with a character which is not
        " a whitespace, but looks like one.
        "}}}
        call map(a:output, { i,v -> {
        \                             'bufnr': v,
        \                             'text': printf(' %*d%s%s%s%s%s %s',
        \                                             len(bufnr('$')), v,
        \                                            !buflisted(v) ? 'u': ' ',
        \                                            v ==# bufnr('%') ? '%' : v ==# bufnr('#') ? '#' : ' ',
        \                                            empty(win_findbuf(v)) ? 'h' : 'a',
        \                                            getbufvar(v, '&ma', 0) ? ' ' : '-',
        \                                            getbufvar(v, '&mod', 0) ? '+' : ' ',
        \                                            empty(bufname(v))
        \                                              ?    '[No Name]'
        \                                              :     fnamemodify(bufname(v), ':t')
        \                                           )
        \                           } })

    elseif a:cmd ==# 'changes'
        call map(a:output, { i,v -> {
        \                             'lnum':  matchstr(v, '\v^%(\s+\d+){1}\s+\zs\d+'),
        \                             'col':   matchstr(v, '\v^%(\s+\d+){2}\s+\zs\d+'),
        \                             'text':  matchstr(v, '\v^%(\s+\d+){3}\s+\zs.*'),
        \                             'bufnr': bufnr(''),
        \                           }
        \                  })
        " all entries should show some text, otherwise it's impossible to know
        " what changed, and they're useless
        call filter(a:output, { i,v -> !empty(v.text) })

    " :Marks! → local marks only
    elseif a:cmd ==# 'marks' && a:bang
        call map(a:output, { i,v -> {
        \                             'mark_name':  matchstr(v, '\S\+'),
        \                             'lnum':       matchstr(v, '\v^\s*\S+\s+\zs\d+'),
        \                             'col':        matchstr(v, '\v^\s*\S+%(\s+\zs\d+){2}'),
        \                             'text':       matchstr(v, '\v^\s*\S+%(\s+\d+){2}\s+\zs.*'),
        \                             'filename':   matchstr(v, '\v^\s*\S+%(\s+\d+){2}\s+\zs.*'),
        \                           }
        \                  })

        "                             ┌─ `remove()` returns the removed item,
        "                             │  but `extend()` does NOT return the added item;
        "                             │  instead returns the new extended dictionary
        "                             │
        let l:Local_mark  = { item -> extend(item, { 'filename': expand('%:p'),
        \                                            'text': item.mark_name.'    '.item.text }) }

        call map(a:output, printf(
        \                          '%s ? %s : %s',
        \                          'v:val.mark_name !~# "^\\u$"',
        \                          'l:Local_mark(v:val)',
        \                          '{}',
        \                        )
        \       )

        " remove possible empty dictionaries  which may have appeared after previous
        " `map()` invocation
        call filter(a:output, { i,v -> !empty(v) })

        " When we iterate  over the dictionaries (`mark`)  stored in `a:output`,
        " we have access to the original dictionaries, not copies.
        " Otherwise,  removing  a  key  from   them  would  have  no  effect  on
        " `a:output`.  But it does.
        " This  is  because  Vim   passes  lists/dictionaries  to  functions  by
        " reference, not by value.
        for mark in a:output
            " remove the `mark_name` key, it's not needed anymore
            call remove(mark, 'mark_name')
        endfor

    " :Marks  → global marks only
    elseif a:cmd ==# 'marks' && !a:bang
        if !filereadable($HOME.'/.vim/bookmarks')
            return []
        endif
        let bookmarks = readfile($HOME.'/.vim/bookmarks')

        call map(bookmarks, { i,v -> {
        \                             'text':       v[0].'  '.fnamemodify(matchstr(v, ':\zs.*'), ':t'),
        \                             'filename':   expand(matchstr(v, ':\zs.*')),
        \                           }
        \                  })

        return bookmarks

    elseif a:cmd ==# 'number'
        call map(a:output, { i,v -> {
        \                             'filename' : expand('%:p'),
        \                             'lnum'     : matchstr(v, '\v^\s*\zs\d+'),
        \                             'text'     : matchstr(v, '\v^\s*\d+\s\zs.*'),
        \                           }
        \                  })

    elseif a:cmd ==# 'oldfiles'
        call map(a:output, { i,v -> {
        \                             'filename' : expand(matchstr(v, '\v^\d+:\s\zs.*')),
        \                             'text'     : fnamemodify(matchstr(v, '\v^\d+:\s\zs.*'), ':t'),
        \                           }
        \                  })

    elseif a:cmd ==# 'registers'
        " Do NOT use the `filename` key to store the name of the registers.
        " Why?
        " After executing `:LReg`, Vim would load buffers "a", "b", …
        " They would pollute the buffer list (`:ls!`).
        call map(a:output, { i,v -> { 'text': v } })

        " We pass `1` as a 2nd argument to `getreg()`.
        " It's ignored  for most registers,  but useful for the  expression register.
        " It allows to get the expression  itself, not its current value which could
        " not exist anymore (ex: a:arg)
        call map(a:output, { i,v -> extend(v, {
        \                                       'text':  v.text
        \                                               .'    '
        \                                               .strtrans(getreg(v.text, 1))
        \                                     })
        \                  })

    endif
    return a:output
endfu

fu! interactive_lists#main(cmd, bang) abort "{{{1
    try
        let cmdline = getcmdline()
        if a:cmd ==# 'number' && cmdline[-1:-1] !=# '#'
            return cmdline
        endif
        let output = s:capture(a:cmd)
        if a:cmd ==# 'number' && get(output, 0, '') =~# '^Pattern not found:'
            call timer_start(0, {-> feedkeys("\<cr>", 'in') })
            return 'echoerr "Pattern not found"'
        endif
        let list = s:convert(output, a:cmd, a:bang ? 1 : 0)

        if empty(list)
            return a:cmd ==# 'args'
            \?         'echoerr "No arguments"'
            \:     a:cmd ==# 'number'
            \?         cmdline
            \:         'echoerr "No output"'
        endif

        call setloclist(0, list)
        call setloclist(0, [], 'a', { 'title': a:cmd ==# 'marks'
        \                                    ?     ':Marks' .(a:bang ? '!' : '')
        \                                    : a:cmd ==# 'number'
        \                                    ?     ':'.cmdline
        \                                    :     ':'.a:cmd.(a:bang ? '!' : '')})

        if a:cmd ==# 'number'
            call timer_start(0, {-> s:open_qf('number') + feedkeys("\e", 'in')})
        else
            call s:open_qf(a:cmd)
        endif
    catch
        return a:cmd ==# 'number'
        \?         cmdline
        \:         lg#catch_error()
    endtry
    return ''
endfu

fu! s:open_qf(cmd) abort "{{{1
    " We don't want to open the qf  window directly, because it's the job of our
    " `vim-qf` plugin. The latter uses some logic to decide the position and the
    " size of the qf window.
    " `:lopen`  or  `:lwindow` would  just  open  the  window with  its  default
    " position/size without any custom logic.
    "
    " So,  we just  emit the  event `QuickFixCmdPost`.  `vim-qf` has  an autocmd
    " listening to it.
    doautocmd <nomodeline> QuickFixCmdPost lopen

    if &bt !=# 'quickfix'
        return
    endif

    let pat = {
    \           'args'      : '.*|\s*|\s*',
    \           'changes'   : '^\v.{-}\|\s*\d+%(\s+col\s+\d+\s*)?\s*\|\s?',
    \           'ls'        : '\v.*\|\s*\|\s*\ze%(\[No Name\]\s*)?.*$',
    \           'marks'     : '\v^.{-}\|.{-}\|\s*',
    \           'number'    : '.*|\s*\d\+\s*|\s\?',
    \           'oldfiles'  : '.\{-}|\s*|\s*',
    \           'registers' : '\v^\s*\|\s*\|\s*',
    \         }[a:cmd]

    call qf#set_matches('interactive_lists:open_qf', 'Conceal', pat)

    if a:cmd ==# 'registers'
        call qf#set_matches('interactive_lists:open_qf', 'qfFileName',  '\v^\s*\|\s*\|\s\zs\S+')
    endif
    call qf#create_matches()
endfu

fu! interactive_lists#set_or_go_to_mark(action) abort "{{{1
    " ask for a mark
    let mark = nr2char(getchar(),1)
    if mark ==# "\e"
        return
    endif

    " if it's not a global one, just type the keys as usual
    "     • mx
    "     • 'x
    if mark !=# toupper(mark)
        return feedkeys((a:action ==# 'set' ? 'm' : "'").mark, 'int')
    endif

    " now, we process a global mark
    " first, get the path to the file containing the bookmarks
    let book_file = $HOME.'/.vim/bookmarks'
    if !filereadable(book_file)
        echo book_file.' is not readable'
        return
    endif

    " we SET a global mark
    if a:action ==# 'set'
        "                   ┌ eliminate old mark if it's present
        "                   │
        let new_bookmarks = filter(readfile(book_file), {i,v -> v[0] !=# mark})
        \ +                 [mark.':'.substitute(expand('%:p'), $HOME, '$HOME', '')]
        " │
        " └ and bookmark current file
        call writefile(sort(new_bookmarks), book_file)

    " we JUMP to a global mark
    else
        let path = filter(readfile(book_file), {i,v -> v[0] ==# mark})
        if empty(path)
            return
        endif
        let path = path[0][2:]
        exe 'e '.path
        " '. may not exist
        try
            sil! norm! g`.zvzz
            "  │
            "  └ E20: mark not set
        catch
            return lg#catch_error()
        endtry
    endif
    " re-mark the file, to fix Vim's frequent and unavoidable lost marks
    call feedkeys('m'.mark, 'int')
endfu
