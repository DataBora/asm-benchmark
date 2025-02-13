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

GENERIC_READ        equ 80000000h
FILE_SHARE_READ     equ 00000001h
OPEN_EXISTING       equ 3
FILE_ATTRIBUTE_NORMAL equ 80h
INVALID_HANDLE_VALUE equ -1
FILE_BEGIN          equ 0
NULL                equ 0
BUFFER_SIZE         equ 500000
MAX_CUSTOMERS       equ 100
ITERATIONS          equ 1000

.data
    filename    db "sales_order_report.csv", 0
    fileHandle  dd 0
    buffer      db BUFFER_SIZE dup(0)
    error_msg   db "Error opening file", 0
    success_msg db "Running benchmark with 1000 iterations...", 13, 10, 0
    bytesRead   dd 0
    
    ; bench vars
    StartTime   dq 0
    EndTime     dq 0
    Frequency   dq 0
    TotalTime   dq 0.0
    IterCount   dd 0
    time_msg    db "Average execution time over %d iterations: %.3f milliseconds", 13, 10, 0
    
    current_customer    db 100 dup(0)
    value_str   db 50 dup(0)
    comma_count dd 0
    
    customer_names db MAX_CUSTOMERS * 100 dup(0)
    customer_totals dq MAX_CUSTOMERS dup(0.0)
    customer_count dd 0
    
    fmt_str     db "Customer: %s, Total Value: %.2f", 13, 10, 0

.code
; Reset arrays and counters
reset_data proc
    push ecx
    push edi
    
    mov customer_count, 0
    xor ecx, ecx       
    
clear_totals:
    cmp ecx, MAX_CUSTOMERS
    jae reset_done
    
    ; Clear the qword using two dword moves
    mov edi, ecx
    shl edi, 3             ; Multiply by 8 for qword offset
    mov dword ptr [customer_totals + edi], 0
    mov dword ptr [customer_totals + edi + 4], 0
    
    inc ecx
    jmp clear_totals
    
reset_done:
    pop edi
    pop ecx
    ret
reset_data endp

; Process single value
process_value proc
    local value:real8
    
    invoke crt_atof, addr value_str
    fstp value
    
    fld value
    mov eax, ebx
    fld qword ptr [customer_totals + eax * 8]
    faddp st(1), st(0)
    fstp qword ptr [customer_totals + eax * 8]
    ret
process_value endp

; Find or add customer
find_customer proc uses esi edi ebx
    mov esi, offset customer_names
    xor ebx, ebx
    
find_loop:
    cmp ebx, [customer_count]
    jae add_new_customer
    
    push offset current_customer
    push esi
    call crt_strcmp
    add esp, 8
    
    test eax, eax
    jz found_customer
    
    add esi, 100
    inc ebx
    jmp find_loop
    
add_new_customer:
    push offset current_customer
    push esi
    call crt_strcpy
    add esp, 8
    
    mov eax, customer_count
    fldz
    fstp qword ptr [customer_totals + eax * 8]
    
    inc eax
    mov customer_count, eax
    
found_customer:
    mov eax, ebx
    ret
find_customer endp

process_csv proc
    mov esi, offset buffer
    add esi, 3  ; Skip BOM
    
    ; Skip header line
skip_header:
    mov al, [esi]
    inc esi
    cmp al, 0Ah
    jne skip_header
    
process_lines:
    mov comma_count, 0
    mov edi, offset current_customer
    mov ebx, offset value_str
    
parse_data:
    mov al, [esi]
    
    cmp al, 0
    je parsing_done
    
    cmp al, 0Ah
    je line_done
    
    cmp al, ','
    je found_comma
    
    cmp comma_count, 0
    jne check_value_field
    mov [edi], al
    inc edi
    jmp next_char
    
check_value_field:
    cmp comma_count, 10
    jne next_char
    mov [ebx], al
    inc ebx
    
next_char:
    inc esi
    jmp parse_data
    
found_comma:
    inc comma_count
    inc esi
    jmp parse_data
    
line_done:
    mov byte ptr [edi], 0
    mov byte ptr [ebx], 0
    
    call find_customer
    mov ebx, eax
    call process_value
    
    inc esi
    jmp process_lines
    
parsing_done:
    ret
process_csv endp

start:
    invoke StdOut, addr success_msg
    
    invoke QueryPerformanceFrequency, addr Frequency
    
    invoke CreateFile, addr filename, GENERIC_READ, FILE_SHARE_READ, NULL, 
                      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL
    mov fileHandle, eax
    
    cmp eax, INVALID_HANDLE_VALUE
    je error_handler

iteration_loop:
    ; Reset file pointer
    push 0
    push 0
    push 0
    push fileHandle
    call SetFilePointer
    
    ; Get start time
    invoke QueryPerformanceCounter, addr StartTime
    
    ; Read and process file
    invoke ReadFile, fileHandle, addr buffer, BUFFER_SIZE, addr bytesRead, NULL
    call process_csv
    
    ; Get end time
    invoke QueryPerformanceCounter, addr EndTime
    
    ; ((EndTime - StartTime) * 1000.0) / Frequency
    fild qword ptr EndTime
    fild qword ptr StartTime
    fsubp st(1), st(0)    ; EndTime - StartTime
    fld1
    fld1
    fld1
    fadd
    fadd
    fmulp st(1), st(0)    ; Multiply by 1000 for milliseconds
    fild qword ptr Frequency
    fdivp st(1), st(0)    ; Divide by frequency
    
    ; Add to total
    fld qword ptr TotalTime
    faddp st(1), st(0)
    fstp qword ptr TotalTime
    
    ; reset
    call reset_data
    
    ; iteration count
    inc IterCount
    mov eax, IterCount
    cmp eax, ITERATIONS
    jl iteration_loop
    
    ; Average: TotalTime / ITERATIONS
    fld qword ptr TotalTime
    fild dword ptr IterCount
    fdivp st(1), st(0)
    
    ; result
    sub esp, 8
    fstp qword ptr [esp]
    push ITERATIONS
    push offset time_msg
    call crt_printf
    add esp, 16
    
done:
    invoke CloseHandle, fileHandle
    jmp exit_prog
    
error_handler:
    invoke StdOut, addr error_msg
    
exit_prog:
    invoke ExitProcess, 0

end start