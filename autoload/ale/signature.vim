" Author: nessanoia <vanessanoia411@gmail.com>
" Description: Signature Help support for LSP linters.

let s:signature_map = {}
let s:open_lnum = 0

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

function! ale#signature#ParseLSPResult(result) abort
    let l:lines = []
    if has_key(a:result, 'signatures')
        let l:signatures = a:result.signatures
    else
        return []
    endif

    for l:signature in l:signatures
        if type(l:signature) is v:t_dict && has_key(l:signature, 'label')
            call add(l:lines, l:signature.label)
        endif
    endfor

    return l:lines
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

        let l:functions = ale#signature#ParseLSPResult(l:result)

        if !empty(l:functions)
            let l:active_param_index = s:GetActiveParameterIndex()

            let l:commands = ['call clearmatches()']
            let [l:add_highlight_commands, l:functions] = s:GetCommandsAndApplicableFunctionsFromActiveIndex(l:functions, l:active_param_index)
            call extend(l:commands, l:add_highlight_commands)

            if g:ale_hover_to_floating_preview || g:ale_floating_preview
                if !s:IsPopupOpen()
                    let s:open_lnum = line('.')
                endif

                call ale#floating_preview#Show(l:functions, {
                \   'moved': [0, 0, 0],
                \   'commands': l:commands,
                \})

                let l:starting_bracket_col = searchpos('(', 'nbW', line('.'))[1]
                let l:closing_bracket_col = searchpos(')', 'cnW', line('.'))[1]+1

                let l:curr_lnum = line('.')
                let l:cursor_col = getpos('.')[2]

                if l:starting_bracket_col == 0 || l:cursor_col > l:closing_bracket_col
                            \ || l:curr_lnum != s:open_lnum
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

function! s:GetActiveParameterIndex() abort
    let l:pair_bracket_pos = searchpairpos('(', '', ')', 'nbW')[1]

    let l:line = getline('.')
    let l:inner_end_bracket = searchpos(')', 'nbW', line('.'))[1]

    if l:inner_end_bracket != 0
        let l:inner_start_bracket = searchpos('(', 'nbW', line('.'))[1]
        let l:line = l:line[l:pair_bracket_pos:l:inner_start_bracket] . l:line[l:inner_end_bracket:getpos('.')[2]-1]
    else
        let l:line = l:line[l:pair_bracket_pos:getpos('.')[2]-1]
    endif

    let l:param_index = count(l:line, ',')
    return l:param_index
endfunction

function! s:GetCommandsAndApplicableFunctionsFromActiveIndex(functions, active_param_index) abort
    let l:commands = []
    let l:applicable_functions = []

    for l:function in a:functions
        let l:parameters = split(l:function, '(\|)\|,')
        if len(l:parameters) - 1 > a:active_param_index
            let l:active_param = l:parameters[a:active_param_index + 1]

            call add(l:applicable_functions, l:function)
            call add(l:commands, 'let m = matchadd("ALESignatureHelp", "' . l:active_param . '")')
        endif
    endfor

    return [l:commands, l:applicable_functions]
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

