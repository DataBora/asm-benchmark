.386
.model flat, stdcall
option casemap:none

include \masm32\include\kernel32.inc
include \masm32\include\masm32.inc
include \masm32\include\user32.inc
include \masm32\include\msvcrt.inc

includelib \masm32\lib\kernel32.lib
includelib \masm32\lib\masm32.lib
includelib \masm32\lib\user32.lib
includelib \masm32\lib\msvcrt.lib

; Constants
GENERIC_READ        equ 80000000h
FILE_SHARE_READ     equ 00000001h
OPEN_EXISTING       equ 3
FILE_ATTRIBUTE_NORMAL equ 80h
INVALID_HANDLE_VALUE equ -1
NULL                equ 0
CHUNK_SIZE      equ 4096
MAX_STR_LEN     equ 1024    

.data
    filename    db "test2.json", 0
    fileHandle  dd 0
    chunk       db CHUNK_SIZE dup(0)
    bytesRead   dd 0
    
    current_key     db MAX_STR_LEN dup(0)
    current_value   db MAX_STR_LEN dup(0)
    key_len         dd 0
    value_len       dd 0
    
    ; State flags
    in_array        db 0
    in_object       db 0
    in_string       db 0
    expect_key      db 1
    last_char       db 0
    
    ; Output formatting
    msg_opening     db "Opening file...", 13, 10, 0
    msg_reading     db "Reading file...", 13, 10, 0
    msg_parsing     db "Parsing JSON...", 13, 10, 0
    msg_summary     db "Number of objects read: ", 0
    found_key       db "  ", 0
    found_value     db ": ", 0
    object_sep      db 13, 10, 0  ; Separator between objects
    newline         db 13, 10, 0
    error_msg       db "Error opening file", 13, 10, 0
    read_error      db "Error reading file", 13, 10, 0
    obj_count       dd 0
    numStr          db 16 dup(0)

.code
start:
    invoke StdOut, addr msg_opening
    
    ; Open file
    invoke CreateFileA, addr filename, GENERIC_READ, FILE_SHARE_READ, NULL, 
                      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL
    mov fileHandle, eax
    
    cmp eax, INVALID_HANDLE_VALUE
    je error_handler
    
    invoke StdOut, addr msg_reading
    invoke StdOut, addr newline

read_chunk:
    ; Clear chunk buffer
    push ecx
    mov ecx, CHUNK_SIZE
    mov edi, offset chunk
    xor al, al
    rep stosb
    pop ecx

    ; Read next chunk
    invoke ReadFile, fileHandle, addr chunk, CHUNK_SIZE, addr bytesRead, NULL
    test eax, eax
    jz read_error_handler
    
    ; Check if we read anything
    mov eax, bytesRead
    test eax, eax
    jz done_reading
    
    ; Process this chunk
    mov esi, offset chunk    ; Source index
    mov edi, offset current_key
    
parse_loop:
    ; Check if we've processed the entire chunk
    mov eax, esi
    sub eax, offset chunk
    cmp eax, bytesRead
    jae read_chunk
    
    mov al, [esi]
    
    ; Check for array start
    cmp al, '['
    jne not_array_start
    mov byte ptr [in_array], 1
    inc esi
    jmp parse_loop
    
not_array_start:
    ; Check for object boundaries
    cmp al, '{'
    jne not_object_start
    
    ; If we were already in an object, print separator
    cmp byte ptr [in_object], 1
    jne no_sep_needed
    invoke StdOut, addr object_sep
    
no_sep_needed:
    inc dword ptr [obj_count]
    mov byte ptr [in_object], 1
    mov edi, offset current_key
    xor ecx, ecx
    mov byte ptr [expect_key], 1
    inc esi
    jmp parse_loop
    
not_object_start:
    ; Check for object end
    cmp al, '}'
    jne not_object_end
    mov byte ptr [in_object], 0
    invoke StdOut, addr newline
    inc esi
    jmp parse_loop
    
not_object_end:
    ; Check for string boundaries
    cmp al, '"'
    jne not_quote
    xor byte ptr [in_string], 1
    inc esi
    jmp parse_loop
    
not_quote:
    ; If we're in a string, collect characters
    cmp byte ptr [in_string], 1
    jne not_string_char
    
    mov [edi], al
    inc edi
    inc ecx
    inc esi
    jmp parse_loop
    
not_string_char:
    ; Check for key-value separator
    cmp al, ':'
    jne not_colon
    
    ; Finish key
    mov key_len, ecx
    mov byte ptr [edi], 0
    
    ; Switch to value buffer
    mov edi, offset current_value
    xor ecx, ecx
    mov byte ptr [expect_key], 0
    inc esi
    jmp parse_loop
    
not_colon:
    ; Check for value end
    cmp al, ','
    je print_pair
    cmp al, '}'    ; Also print pair when object ends
    je end_object
    
    ; If not special character and not whitespace, collect it
    cmp al, 20h    ; space
    je skip_char
    cmp al, 09h    ; tab
    je skip_char
    cmp al, 0Ah    ; LF
    je skip_char
    cmp al, 0Dh    ; CR
    je skip_char
    
    mov [edi], al
    inc edi
    inc ecx
    
skip_char:
    inc esi
    jmp parse_loop

end_object:
    ; First print the last pair
    push esi       ; Save position
    call print_pair_internal
    pop esi        ; Restore position
    
    ; Now handle object end
    mov byte ptr [in_object], 0
    invoke StdOut, addr newline
    inc esi
    jmp parse_loop
    
print_pair:
    call print_pair_internal
    inc esi
    jmp parse_loop

print_pair_internal:
    ; Only print if we have a key
    cmp key_len, 0
    je skip_print
    
    ; Null terminate value
    mov byte ptr [edi], 0
    
    ; Print key-value pair
    invoke StdOut, addr found_key
    invoke StdOut, addr current_key
    invoke StdOut, addr found_value
    invoke StdOut, addr current_value
    invoke StdOut, addr newline
    
skip_print:
    ; Reset for next pair
    mov edi, offset current_key
    xor ecx, ecx
    mov byte ptr [expect_key], 1
    mov key_len, 0
    ret
    
done_reading:
    ; Print summary
    invoke StdOut, addr newline
    invoke StdOut, addr msg_summary
    invoke dwtoa, obj_count, addr numStr
    invoke StdOut, addr numStr
    invoke StdOut, addr newline
    
    invoke CloseHandle, fileHandle
    jmp exit_prog
    
read_error_handler:
    invoke StdOut, addr read_error
    jmp cleanup_and_exit

error_handler:
    invoke StdOut, addr error_msg
    
cleanup_and_exit:
    cmp fileHandle, INVALID_HANDLE_VALUE
    je exit_prog
    invoke CloseHandle, fileHandle
    
exit_prog:
    invoke ExitProcess, 0

end start