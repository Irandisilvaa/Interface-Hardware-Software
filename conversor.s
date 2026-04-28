.intel_syntax noprefix
.global main

.section .bss
    text_buffer: .space 10485760   # 10 MB para o texto de entrada
    text_ptr:    .quad 0         
    
    buffer_in:   .space 5242880    # 5 MB para os dados parseados
    palette:     .space 16        
    
    image_buf:   .space 70000      # Buffer da imagem atual
    num_str:     .space 32        
    fd_in:       .quad 0          
    fd_out:      .quad 0          

.section .data
    msg_bracket1: .ascii "["
    msg_bracket2: .ascii "%]\n"
    msg_newline:  .ascii "\n"

.section .text
main:
    cmp rdi, 3
    jl exit_error

    mov r12, rsi                

    # open input
    mov rax, 2
    mov rdi, [r12 + 8]
    mov rsi, 0
    syscall
    cmp rax, 0
    jl exit_error
    mov [rip + fd_in], rax            

    # open output
    mov rax, 2
    mov rdi, [r12 + 16]
    mov rsi, 577
    mov rdx, 0644
    syscall
    cmp rax, 0
    jl exit_error
    mov [rip + fd_out], rax            

    # read file
    mov rdi, [rip + fd_in]
    lea rsi, [rip + text_buffer]

read_loop:
    mov rax, 0
    mov rdx, 65536
    syscall
    cmp rax, 0
    jle end_read
    add rsi, rax
    jmp read_loop

end_read:
    mov byte ptr [rsi], 0

    lea rsi, [rip + text_buffer]
    mov [rip + text_ptr], rsi
    lea rbx, [rip + buffer_in]

    # palette
    mov rcx, 16
parse_pal:
    push rcx
    call get_hex
    pop rcx
    mov [rbx], al
    inc rbx
    loop parse_pal

    # N images
    call get_dec
    mov [rbx], eax
    add rbx, 4
    mov r15d, eax

parse_images:
    test r15d, r15d
    jz parse_done

    call get_dec
    mov [rbx], eax
    add rbx, 4
    mov r12d, eax

    mov rcx, r12
    imul rcx, 3
    test rcx, rcx
    jz next_parse_img

parse_tuples:
    push rcx
    call get_hex
    pop rcx
    mov [rbx], al
    inc rbx
    loop parse_tuples

next_parse_img:
    dec r15d
    jmp parse_images

parse_done:
    lea rsi, [rip + buffer_in]

    lea rdi, [rip + palette]
    mov ecx, 16
    rep movsb

    mov r15d, [rsi]
    add rsi, 4

image_loop:
    test r15d, r15d
    jz finalize

    mov r12d, [rsi]
    add rsi, 4
    mov r14, rsi

    xor r8, r8
    mov rcx, r12
    mov rsi, r14

scan_width:
    test rcx, rcx
    jz end_width
    movzx eax, byte ptr [rsi]
    cmp eax, r8d
    cmovg r8d, eax
    add rsi, 3
    dec rcx
    jmp scan_width

end_width:
    inc r8d
    test r8d, r8d
    jz next_image   # evita div por zero

    xor r9, r9
    mov rcx, r12
    mov rsi, r14

scan_height:
    test rcx, rcx
    jz end_height

    movzx eax, byte ptr [rsi]
    movzx ebx, byte ptr [rsi+1]
    movzx edx, byte ptr [rsi+2]
    shr edx, 4

    imul ebx, r8d
    add ebx, eax
    add ebx, edx

    cmp ebx, r9d
    cmovg r9d, ebx

    add rsi, 3
    dec rcx
    jmp scan_height

end_height:
    mov eax, r9d
    add eax, r8d
    dec eax
    xor edx, edx
    div r8d
    mov r9d, eax

    # taxa
    mov eax, r12d
    imul eax, 300
    mov ecx, r8d
    imul ecx, r9d
    test ecx, ecx
    jz zero_taxa
    xor edx, edx
    div ecx
    jmp save_taxa

zero_taxa:
    xor eax, eax

save_taxa:
    mov r13d, eax

    # checagem forte de buffer
    mov ecx, r8d
    imul ecx, r9d
    cmp ecx, 70000
    jg next_image

    # limpa buffer
    lea rdi, [rip + image_buf]
    mov al, ' '
    rep stosb

    mov rsi, r14
    mov rcx, r12

render_loop:
    test rcx, rcx
    jz print_image     

    movzx eax, byte ptr [rsi]
    movzx ebx, byte ptr [rsi+1]
    movzx edx, byte ptr [rsi+2]

    mov edi, edx
    shr edi, 4
    and edx, 0x0F

    lea rbp, [rip + palette]
    mov r10b, [rbp + rdx]

    imul ebx, r8d
    add ebx, eax

    lea r11, [rip + image_buf]

fill_loop:
    test edi, edi
    jz end_fill

    cmp ebx, 70000   
    jge print_image   # Se bater na parede de segurança, imprime o que já tem em vez de pular a imagem

    mov byte ptr [r11 + rbx], r10b
    inc ebx
    dec edi
    jmp fill_loop

end_fill:
    add rsi, 3
    dec rcx
    jmp render_loop

print_image:
    # Imprime "["
    mov rax, 1
    mov rdi, [rip + fd_out]
    lea rsi, [rip + msg_bracket1]
    mov rdx, 1
    syscall

    # Imprime a Taxa
    mov eax, r13d
    call print_dec

    # Imprime "%]\n"
    mov rax, 1
    mov rdi, [rip + fd_out]
    lea rsi, [rip + msg_bracket2]
    mov rdx, 3
    syscall

    xor ebx, ebx       # Y atual = 0
print_y:
    cmp ebx, r9d
    jge next_image

    # Escreve a linha inteira de uma vez
    mov rax, 1
    mov rdi, [rip + fd_out]
    lea rsi, [rip + image_buf]
    mov eax, ebx
    imul eax, r8d      # Offset = Y * Width
    add rsi, rax       
    mov rdx, r8        # Tamanho = Width
    mov rax, 1
    syscall

    # Pula linha
    mov rax, 1
    mov rdi, [rip + fd_out]
    lea rsi, [rip + msg_newline]
    mov rdx, 1
    syscall

    inc ebx
    jmp print_y

next_image:
    mov eax, r12d
    imul eax, 3
    add r14, rax
    mov rsi, r14
    dec r15d
    jmp image_loop

finalize:
    mov rax, 3
    mov rdi, [rip + fd_in]
    syscall

    mov rax, 3
    mov rdi, [rip + fd_out]
    syscall

    mov rax, 60
    xor rdi, rdi
    syscall

exit_error:
    mov rax, 60
    mov rdi, 1
    syscall

# --- PARSERS e UTILS ---

get_hex:
    mov rsi, [rip + text_ptr]
    xor eax, eax

.skip_hex:
    movzx edx, byte ptr [rsi]
    test dl, dl
    jz .done_hex
    cmp dl, 32
    jg .read_hex
    inc rsi
    jmp .skip_hex

.read_hex:
    movzx edx, byte ptr [rsi]
    test dl, dl
    jz .done_hex
    cmp dl, 32
    jle .done_hex

    inc rsi

    cmp dl, '0'
    jl .done_hex
    cmp dl, '9'
    jle .num_hex
    and dl, 0xDF
    sub dl, 'A'
    cmp dl, 5
    ja .done_hex
    add dl, 10
    jmp .acc_hex

.num_hex:
    sub dl, '0'

.acc_hex:
    shl eax, 4
    add eax, edx
    jmp .read_hex

.done_hex:
    mov [rip + text_ptr], rsi
    ret


get_dec:
    mov rsi, [rip + text_ptr]
    xor eax, eax

.skip_dec:
    movzx edx, byte ptr [rsi]
    test dl, dl
    jz .done_dec
    cmp dl, 32
    jg .read_dec
    inc rsi
    jmp .skip_dec

.read_dec:
    movzx edx, byte ptr [rsi]
    cmp dl, '0'
    jl .done_dec
    cmp dl, '9'
    jg .done_dec

    inc rsi
    sub dl, '0'
    imul eax, 10
    add eax, edx
    jmp .read_dec

.done_dec:
    mov [rip + text_ptr], rsi
    ret


print_dec:
    lea rsi, [rip + num_str + 30]
    mov byte ptr [rsi], 0
    mov ecx, 10
.pd_loop:
    xor edx, edx
    div ecx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test eax, eax
    jnz .pd_loop

    lea rdx, [rip + num_str + 30]
    sub rdx, rsi
    mov rax, 1
    mov rdi, [rip + fd_out]
    syscall
    ret

    