" Author: nessanoia <vanessanoia411@gmail.com>
" Description: Signature Help support for LSP linters.

let s:signature_map = {}
let s:open_lnum = 0
let w:active_parameter = 0

if !hlexists('ALESigntureHelp')
    highlight ALESignatureHelp cterm=reverse gui=reverse
endif

autocmd CursorMoved * call ale#floating_preview#VimClose()

function! ale#signature#ClearLSPData() abort
    let s:signature_map = {}
endfunction

function! ale#signature#HandleTSServerResponse(conn_id, response) abort
    if get(a:response, 'command', '') is# 'quickinfo'
    \&& has_key(s:signature_map, a:response.request_seq)
        let l:options = remove(s:signature_map, a:response.request_seq)

        if get(a:response, 'success', v:false) is v:true
        \&& get(a:response, 'body', v:null) isnot v:null
            elseif get(l:options, 'hover_from_balloonexpr', 0)
            \&& exists('*balloon_show')
            \&& (l:set_balloons is 1 || l:set_balloons is# 'hover')
                call balloon_show(a:response.body.displayString)
            elseif get(l:options, 'truncated_echo', 0)
                if !empty(a:response.body.displayString)
                    call ale#cursor#TruncatedEcho(a:response.body.displayString)
                endif
            elseif g:ale_hover_to_floating_preview || g:ale_floating_preview
                call ale#floating_preview#Show(split(a:response.body.displayString, "\n"), {
                \   'filetype': 'ale-preview.message',
                \})
            elseif g:ale_hover_to_preview
                call ale#preview#Show(split(a:response.body.displayString, "\n"), {
                \   'filetype': 'ale-preview.message',
                \   'stay_here': 1,
                \})
            else
                call ale#util#ShowMessage(a:response.body.displayString)
            endif
        endif
endfunction

" Convert a language name to another one.
" The language name could be an empty string or v:null
function! s:ConvertLanguageName(language) abort
    return a:language
endfunction

" Cache syntax file (non-)existence to avoid calling globpath repeatedly.
let s:syntax_file_exists_cache = {}

function! s:SyntaxFileExists(syntax_file) abort
    if !has_key(s:syntax_file_exists_cache, a:syntax_file)
        let s:syntax_file_exists_cache[a:syntax_file] =
        \   !empty(globpath(&runtimepath, a:syntax_file))
    endif

    return s:syntax_file_exists_cache[a:syntax_file]
endfunction

function! ale#signature#ParseLSPResult(result) abort
    let l:includes = {}
    let l:lines = []
    let l:region_index = 0
    if has_key(a:result, 'signatures')
        let l:signatures = a:result.signatures
    else
        return
    endif
    let l:list = type(a:result) is v:t_list ? a:result : [a:result]
		let l:highlights = []

		
		" call add(l:highlights, 
			" :highlight MyGroup ctermbg=green guibg=green
			" :let m = matchaddpos("MyGroup", [[23, 24], 34])


		if has_key(a:result, 'activeSignature')
			return []
			" let l:signature = l:signatures[a:active_signature]
		elseif len(l:signatures) == 1
			let l:signature = l:signatures[0]
		else
			" TODO: Loop over signatures and display all that apply. Think in like java or c++. Once I do that I can probably
			" get rid of the above elseif case
			return []
		endif

	" matchstr(getline(a:line)[: a:column - 2], l:regex)

		" if has_key(a:result, 'activeParameter') || has_key(l:signature, 'activeParameter')
		" else
		" endif

		if !empty(l:lines)
			call add(l:lines, '')
		endif

		if type(l:signature) is v:t_dict
			call add(l:lines, l:signature.label)
		endif



    return [l:highlights, l:lines]
endfunction

function! ale#signature#HandleLSPResponse(conn_id, response) abort
    if has_key(a:response, 'id')
    \&& has_key(s:signature_map, a:response.id)
        let l:options = remove(s:signature_map, a:response.id)

        " The result can be a Dictionary item, a List of the same, or null.
        let l:result = get(a:response, 'result', v:null)

        if l:result is v:null
            return
        endif

        let [l:commands, l:function] = ale#signature#ParseLSPResult(l:result)

				" So my thought process here, is count the number of commas before the cursor. And then use that number to know
				" how many things in (what parameter number) to highlight.

				" we want to look at the commas that are since the last unmatched (
				" Get the string on the line before the cursor.
				"
				" Remove nested inner functions
				" Count the number of commas before the cursor
				" If zero: use first param regex
				" If 1+: we need to write regex that takes in a number I think
				" let l:line = getline('.')[:col('.')-2]
				" let l:function_started_col = searchpos('(', 'nb')[1]
				" let l:function_ended_col = searchpos(')', 'nb')[1]
				" let l:function_started_col = searchpairpos('(', '', ')', 'nbW')[1]

				" let l:params_no_nested = l:line[l:function_started_col:]
				" let l:params = l:line[l:function_started_col:]


				" let l:test = searchpairpos('(', '', ')', 'nW')
				" echom l:test

				" let l:param_index = len(split(getline(a:lnum), ',', 1)) - 1
				" let l:regex = '"\\v((\\(|,){1})\\zs((\\(|\\)|,)@!)\\ze(,.*|\\))"'
				" let l:regex_test = '\v(\(|,)\zs[^\(\),]*'
				" let l:matchlist = matchlist(getline('.'), l:regex_test)
				" echom l:matchlist
				" call add(l:commands, 'let m = matchadd("ALESignatureHelp", ' . l:regex . ')')

        if !empty(l:function)
            if g:ale_hover_to_floating_preview || g:ale_floating_preview
								if !s:IsPopupOpen()
										let s:open_lnum = line('.')
								endif

								let l:pair_bracket_pos = searchpairpos('(', '', ')', 'nbW')[1]
								echom l:pair_bracket_pos
    						call ale#floating_preview#Show(l:function, {
								\		'col': l:pair_bracket_pos,
								\   'moved': [0, 0, 0],
								\   'commands': l:commands,
								\})

								let l:starting_bracket_pos = searchpos('(', 'cnW', line('.'))[1]
								let l:closing_bracket_pos = searchpos(')','nbW', line('.'))[1]
								let l:curr_lnum = line('.')
								
								if l:starting_bracket_pos != 0 || l:closing_bracket_pos != 0 ||
											\ l:curr_lnum != s:open_lnum
										call ale#floating_preview#VimClose()
								endif

            elseif g:ale_hover_to_preview
                call ale#preview#Show(l:function)
            else
                call ale#util#ShowMessage(join(l:function, "\n"))
            endif
        endif
    endif
endfunction

function! s:IsPopupOpen() abort
    if !exists('w:preview')
        return 0
    endif
		return 1
endfunction

function! s:OnReady(line, column, opt, linter, lsp_details) abort
    let l:id = a:lsp_details.connection_id

    if !ale#lsp#HasCapability(l:id, 'signatureHelp')
        return
    endif

    let l:buffer = a:lsp_details.buffer

    let l:Callback = a:linter.lsp is# 'tsserver'
    \   ? function('ale#signature#HandleTSServerResponse')
    \   : function('ale#signature#HandleLSPResponse')
    call ale#lsp#RegisterCallback(l:id, l:Callback)

    if a:linter.lsp is# 'tsserver'
        let l:column = a:column

        let l:message = ale#lsp#tsserver_message#Quickinfo(
        \   l:buffer,
        \   a:line,
        \   l:column
        \)
    else
        " Send a message saying the buffer has changed first, or the
        " hover position probably won't make sense.
        call ale#lsp#NotifyForChanges(l:id, l:buffer)

        let l:column = max([
        \   min([a:column, len(getbufline(l:buffer, a:line)[0])]),
        \   1,
        \])

        let l:message = ale#lsp#message#SignatureHelp(l:buffer, a:line, l:column)
    endif

    let l:request_id = ale#lsp#Send(l:id, l:message)

    let s:signature_map[l:request_id] = {
    \   'buffer': l:buffer,
    \   'line': a:line,
    \   'column': l:column,
    \}
endfunction

" Obtain SignatureHelp information for the specified position
" Pass optional arguments in the dictionary opt.
" Currently, only one key/value is useful:
"   - called_from_balloonexpr, this flag marks if we want the result from this
"     ale#hover#Show to display in a balloon if possible
"
" Currently, the callbacks displays the info from hover :
" - in the balloon if opt.called_from_balloonexpr and balloon_show is detected
" - as status message otherwise
function! ale#signature#Show(buffer, line, col, opt) abort
    let l:Callback = function('s:OnReady', [a:line, a:col, a:opt])
    for l:linter in ale#lsp_linter#GetEnabled(a:buffer)
       call ale#lsp_linter#StartLSP(a:buffer, l:linter, l:Callback)
    endfor
endfunction

let s:last_pos = [0, 0, 0]

" This function implements the :ALESignatureHelp command.
function! ale#signature#ShowAtCursor() abort
    let l:buffer = bufnr('')
    let l:pos = getpos('.')

    call ale#signature#Show(l:buffer, l:pos[1], l:pos[2], {})
endfunction

