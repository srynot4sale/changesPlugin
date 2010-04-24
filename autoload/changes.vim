" Changes.vim - Using Signs for indicating changed lines
" ---------------------------------------------------------------
" Version:  0.8
" Authors:  Christian Brabandt <cb@256bit.org>
" Last Change: Mon, 19 Apr 2010 15:10:16 +0200


" Script:  http://www.vim.org/scripts/script.php?script_id=3052
" License: VIM License
" Documentation: see :help changesPlugin.txt
" GetLatestVimScripts: 3052 8 :AutoInstall: ChangesPlugin.vim

" Documentation:"{{{1
" See :h ChangesPlugin.txt

" Check preconditions"{{{1
fu! s:Check()
    if !has("diff")
	call add(s:msg,"Diff support not available in your Vim version.")
	call add(s:msg,"changes plugin will not be working!")
	finish
    endif

    if  !has("signs")
	call add(s:msg,"Sign Support support not available in your Vim version.")
	call add(s:msg,"changes plugin will not be working!")
	finish
    endif

    if !executable("diff") || executable("diff") == -1
	call add(s:msg,"No diff executable found")
	call add(s:msg,"changes plugin will not be working!")
	finish
    endif

    " Check for the existence of unsilent
    if exists(":unsilent")
	let s:cmd='unsilent echomsg'
    else
	let s:cmd='echomsg'
    endif

    let s:sign_prefix = 99
    let s:ids={}
    let s:ids["add"]   = hlID("DiffAdd")
    let s:ids["del"]   = hlID("DiffDelete")
    let s:ids["ch"]    = hlID("DiffChange")
    let s:ids["ch2"]   = hlID("DiffText")

endfu

fu! s:WarningMsg()"{{{1
    redraw!
    if !empty(s:msg)
	let msg=["Changes.vim: " . s:msg[0]] + s:msg[1:]
	echohl WarningMsg
	for line in msg
		exe s:cmd "line"
	endfor

	echohl Normal
	let v:errmsg=msg[0]
    endif
endfu

fu! changes#Output()"{{{1
    if s:verbose
	echohl Title
	echo "Differences will be highlighted like this:"
	echohl Normal
	echo "========================================="
	echohl DiffAdd
	echo "+ Added Lines"
	echohl DiffDelete
	echo "- Deleted Lines"
	echohl DiffChange
	echo "* Changed Lines"
	echohl Normal
    endif
endfu

fu! s:Init()"{{{1
    " Only check the first time this file is loaded
    " It should not be neccessary to check every time
    if !exists("s:precheck")
	call s:Check()
	let s:precheck=1
    endif
    let s:hl_lines = (exists("g:changes_hl_lines")  ? g:changes_hl_lines   : 0)
    let s:autocmd  = (exists("g:changes_autocmd")   ? g:changes_autocmd    : 0)
    let s:verbose  = (exists("g:changes_verbose")   ? g:changes_verbose    : 1)
    " Buffer queue, that will be displayed.
    let s:msg      = []
    " Check against a file in a vcs system
    let s:vcs      = (exists("g:changes_vcs_check") ? g:changes_vcs_check  : 0)
    if !exists("s:vcs_cat")
	let s:vcs_cat  = {'git': 'show HEAD:', 
			 \'bzr': 'cat ', 
			 \'cvs': '-q update -p ',
			 \'svn': 'cat ',
			 \'subversion': 'cat ',
			 \'svk': 'cat ',
			 \'hg': 'cat ',
			 \'mercurial': 'cat '}
    endif

    " Settings for Version Control
    if s:vcs
       if !exists("g:changes_vcs_system")
	   call add(s:msg,"Please specify which VCS to use. See :h changes-vcs.")
	   call add(s:msg,"VCS check will be disabled for now.")
	   throw 'changes:NoVCS'
	   sleep 2
	   let s:vcs=0
      endif
      let s:vcs_type  = g:changes_vcs_system
      if get(s:vcs_cat, s:vcs_type)
	   call add(s:msg,"Don't know VCS " . s:vcs_type)
	   call add(s:msg,"VCS check will be disabled for now.")
	   throw 'changes:NoVCS'
	   sleep 2
	   let s:vcs=0
      endif
      if !exists("s:temp_file")
	  let s:temp_file=tempname()
      endif
    endif

    " This variable is a prefix for all placed signs.
    " This is needed, to not mess with signs placed by the user
    let s:signs={}
    let s:signs["add"] = "texthl=DiffAdd text=+ texthl=DiffAdd " . ( (s:hl_lines) ? " linehl=DiffAdd" : "")
    let s:signs["del"] = "texthl=DiffDelete text=- texthl=DiffDelete " . ( (s:hl_lines) ? " linehl=DiffDelete" : "")
    let s:signs["ch"] = "texthl=DiffChange text=* texthl=DiffChange " . ( (s:hl_lines) ? " linehl=DiffChange" : "")

    call s:DefineSigns()
    call s:AuCmd(s:autocmd)
endfu

fu! s:AuCmd(arg)"{{{1
    if s:autocmd && a:arg
	augroup Changes
		autocmd!
		au InsertLeave,CursorHold * :call s:UpdateView()
	augroup END
    else
	augroup Changes
		autocmd!
	augroup END
    endif
endfu

fu! s:DefineSigns()"{{{1
    for key in keys(s:signs)
	exe "sign define" key s:signs[key]
    endfor
endfu

fu! s:CheckLines(arg)"{{{1
    " a:arg  1: check original buffer
    "        0: check diffed scratch buffer
    let line=1
    " This should not be necessary, since b:diffhl for the scratch buffer
    " should never be accessed. But just to be sure, we define it here
"    if (!a:arg) && !exists("b:diffhl")
"	let b:diffhl = {'del': []}
"    endif
    while line <= line('$')
	let id=diff_hlID(line,1)
	if  (id == 0)
	    let line+=1
	    continue
	" in the original buffer, there won't be any lines accessible
	" that have been 'marked' deleted, so we need to check scratch
	" buffer for added lines
	elseif (id == s:ids['add']) && !a:arg
	    let s:temp['del']   = s:temp['del'] + [ line ]
	elseif (id == s:ids['add']) && a:arg
	    let b:diffhl['add'] = b:diffhl['add'] + [ line ]
	elseif ((id == s:ids['ch']) || (id == s:ids['ch2']))  && a:arg
	    let b:diffhl['ch']  = b:diffhl['ch'] + [ line ]
	endif
	let line+=1
    endw
endfu

fu! s:UpdateView()"{{{1
    if !exists("b:changes_chg_tick")
	let b:changes_chg_tick = 0
    endif
    " Only update, if there have been changes to the buffer
    if  b:changes_chg_tick != b:changedtick
	call changes#GetDiff()
    endif
endfu

fu! changes#GetDiff(arg)"{{{1
    " a:arg == 1 Create signs
    " a:arg == 2 Show Overview Window
    " a:arg == 3 Start diff mode
    try
	call s:Init()
    catch changes:NoVCS
	let s:verbose = 0
	return
    endtry

    " Does not make sense to check an empty buffer
    if empty(bufname(''))
	call add(s:msg,"The buffer does not contain a name. Check aborted!")
	let s:verbose = 0
	return
    endif

    " Save some settings
    " fdm, wrap, and fdc will be reset by :diffoff!
    let o_lz   = &lz
    let o_fdm  = &fdm
    let o_fdc  = &fdc
    let o_wrap = &wrap
    " Lazy redraw
    setl lz
    " For some reason, getbufvar/setbufvar do not work, so
    " we use a temporary script variable here
    let s:temp = {'del': []}
    " Delete previously placed signs
    "sign unplace *
    call s:UnPlaceSigns()
    let b:diffhl={'add': [], 'del': [], 'ch': []}
    try
	call s:MakeDiff()
	call s:CheckLines(1)
	" Switch to other buffer and check for deleted lines
	noa wincmd p
	call s:CheckLines(0)
	noa wincmd p
	let b:diffhl['del'] = s:temp['del']
	" Check for empty dict of signs
	if (empty(values(b:diffhl)[0]) && 
	   \empty(values(b:diffhl)[1]) && 
	   \empty(values(b:diffhl)[2]))
	    call add(s:msg, 'No differences found!')
	else
	    call s:PlaceSigns(b:diffhl)
	endif
	call s:DiffOff()
	" :diffoff resets some options (see :h :diffoff
	" so we need to restore them here
	let &fdm=o_fdm
	if  o_fdc ==? 1
	    " When foldcolumn is 1, folds won't be shown because of
	    " the signs, so increasing its value by 1 so that folds will
	    " also be shown
	    let &fdc += 1
	else
	    let &fdc = o_fdc
	endif
	let &wrap = o_wrap
	let b:changes_view_enabled=1
	if a:arg ==# 2
	   call s:ShowDifferentLines()
	endif
    catch /^changes/
	let b:changes_view_enabled=0
	let s:verbose = 0
    finally
	let &lz=o_lz
	if s:vcs && b:changes_view_enabled
	    call add(s:msg,"Check against " . fnamemodify(expand("%"),':t') . " from " . g:changes_vcs_system)
	    call add(s:msg,s:msg)
	endif
	call s:WarningMsg()
    endtry
endfu

fu! s:PlaceSigns(dict)"{{{1
    for [ id, lines ] in items(a:dict)
	for item in lines
	    exe "sign place " s:sign_prefix . item . " line=" . item . " name=" . id . " buffer=" . bufnr('')
	endfor
    endfor
endfu

fu! s:UnPlaceSigns()"{{{1
    redir => a
    silent sign place
    redir end
    let b=split(a,"\n")
    let b=filter(b, 'v:val =~ "id=".s:sign_prefix')
    let b=map(b, 'matchstr(v:val, ''id=\zs\d\+'')')
    for id in b
	exe "sign unplace" id
    endfor
endfu

fu! s:MakeDiff()"{{{1
    " Get diff for current buffer with original
    noa vert new
    set bt=nofile
    if !s:vcs
	r #
    else
	try
	    if !executable(s:vcs_type)
		call add(s:msg,"Executable " . s:vcs_type . "not found! Aborting.")
		throw "changes:abort"
	    endif
	    if s:vcs_type == 'git'
		let git_rep_p = s:ReturnGitRepPath()
	    else
		let git_rep_p = ''
	    endif
	    exe ':silent !' s:vcs_type s:vcs_cat[s:vcs_type] .  git_rep_p . expand("#") '>' s:temp_file
	    let fsize=getfsize(s:temp_file)
	    if fsize == 0
		call delete(s:temp_file)
		call add(s:msg,"Couldn't get VCS output, aborting")
		:q!
		throw "changes:abort"
	    endif
	    exe ':r' s:temp_file
	    call delete(s:temp_file)
        catch /^changes: No git Repository found/
	    call add(s:msg,"Unable to find git Top level repository.")
	    echo v:errmsg
	    :q!
	    throw "changes:abort"
	endtry
    endif
    0d_
    diffthis
    noa wincmd p
    diffthis
endfu

fu! s:ReturnGitRepPath() "{{{1
    " return the top level of the repository path. This is needed, so
    " git show will correctly return the file
    let file  =  fnamemodify(expand("#"), ':p')
    let path  =  fnamemodify(file, ':h')
    let dir   =  finddir('.git',path.';')
    if empty(dir)
	throw 'changes: No git Repository found'
    else
	let ldir  =  strlen(substitute(dir, '.', 'x', 'g'))-4
	return file[ldir :]
    endif
endfu


fu! s:DiffOff()"{{{1
    " Turn off Diff Mode and close buffer
    wincmd p
    diffoff!
    q
endfu

fu! changes#CleanUp()"{{{1
    " only delete signs, that have been set by this plugin
    call s:UnPlaceSigns()
    for key in keys(s:signs)
	exe "sign undefine " key
    endfor
    if s:autocmd
	call s:AuCmd(0)
    endif
endfu

fu! changes#TCV()"{{{1
    if  exists("b:changes_view_enabled") && b:changes_view_enabled
        DC
        let &fdc=b:ofdc
        let b:changes_view_enabled = 0
        echo "Hiding changes since last save"
    else
	call changes#GetDiff()
        let b:changes_view_enabled = 1
        echo "Showing changes since last save"
    endif
endfunction


fu! s:ShowDifferentLines()"{{{1
    redir => a
    silent sign place
    redir end
    let b=split(a,"\n")
    let b=filter(b, 'v:val =~ "id=".s:sign_prefix')
    let b=map(b, 'matchstr(v:val, ''line=\zs\d\+'')')
    let b=map(b, '''\%(^\%''.v:val.''l\)''')
    if !empty(b)
	exe ":silent! lvimgrep /".join(b, '\|').'/gj' expand("%")
	lw
    else
	" This should not happen!
	call setloclist(winnr(),[],'a')
	lclose
	call add(s:msg,"There have been no changes!")
    endif
endfun

fu! s:GuessVCSSystem() "{{{1
    " Check global config variable
    if exists("g:changes_vcs_system")
	let vcs=matchstr(g:changes_vcs_system, '\(git\)\|\(hg\)\|\(bzr\)\|\(svk\)\|\(cvs\)\|\(svn\)')
	if vcs
	    return vcs
	endif
    endif
    let file = fnamemodify(expand("%"), ':p')
    let path = fnamemodify(file, ':h')
    " First let's try if there is a CVS dir
    if isdirectory(path . '/CVS')
	return 'cvs'
    elseif isdirectory(path . '/.svn')
	return 'svn'
    endif
    if !empty(finddir('.git',path.';'))
	return 'git'
    elseif !empty(finddir('.hg',path.';'))
	return 'hg'
    elseif !empty(finddir('.bzr',path.';'))
	return 'bzr'
    else
	"Fallback: svk
	return 'svk'
    endif
endfu
" Modeline "{{{1
" vi:fdm=marker fdl=0
