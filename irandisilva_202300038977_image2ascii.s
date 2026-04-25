.intel_syntax noprefix
.global main

.section .bss
    text_buffer: .space 5242880  # Buffer de 5 MB para o arquivo .txt puro
    text_ptr:    .quad 0         # Ponteiro de leitura do texto
    
    buffer_in:  .space 1048576   # Buffer de 1 MB para a versão binária convertida
    palette:    .space 16        # Paleta de cores (16 bytes)
    image_buf:  .space 65536     # Buffer de 64 KB para a imagem (suporta até 255x255)
    num_str:    .space 32        # Buffer para conversão de números em string
    fd_in:      .quad 0          # File descriptor de entrada
    fd_out:     .quad 0          # File descriptor de saída

.section .data
    msg_bracket1: .ascii "["
    msg_bracket2: .ascii "%]\n"
    msg_newline:  .ascii "\n"

.section .text
main:
    # Verifica argumentos de linha de comando (argc >= 3)
    cmp rdi, 3                  
    jl exit_error               

    # Salva ponteiro para argv em r12
    mov r12, rsi                

    # Abre arquivo de entrada (argv[1]) em modo leitura
    mov rax, 2                  
    mov rdi, [r12 + 8]          
    mov rsi, 0                  
    syscall
    mov [rip + fd_in], rax            

    # Abre arquivo de saída (argv[2]) em modo escrita/criação
    mov rax, 2                  
    mov rdi, [r12 + 16]         
    mov rsi, 577                
    mov rdx, 0644               
    syscall
    mov [rip + fd_out], rax           

    # Leitura do arquivo de texto em blocos para suportar arquivos grandes
    mov rdi, [rip + fd_in]            
    lea rsi, [rip + text_buffer]      
    
read_loop:
    mov rax, 0                  
    mov rdx, 65536              # Lê blocos de 64 KB por vez
    syscall

    cmp rax, 0                  
    jle end_read                # Sai do loop se chegou ao fim do arquivo
    
    add rsi, rax                # Avança o ponteiro pelo número de bytes lidos
    jmp read_loop

end_read:
    mov byte ptr [rsi], 0       # Adiciona terminador nulo para o parser parar com segurança

    # Configura ponteiros para iniciar o parse do texto para binário
    lea rsi, [rip + text_buffer]
    mov [rip + text_ptr], rsi
    lea rbx, [rip + buffer_in]        

    # Lê os 16 bytes da paleta
    mov rcx, 16
parse_pal:
    push rcx
    call get_hex
    pop rcx
    mov [rbx], al
    inc rbx
    loop parse_pal

    # Lê a quantidade de imagens (n)
    call get_dec
    mov [rbx], al
    inc rbx
    mov r15d, eax               

parse_images:
    test r15d, r15d
    jz parse_done

    # Lê a quantidade de tuplas da imagem atual (m)
    call get_dec
    mov [rbx], al
    inc rbx
    mov r12d, eax               

    # Calcula e lê os bytes correspondentes às tuplas (m * 3)
    mov rcx, r12
    imul rcx, 3
    test rcx, rcx
    jz parse_img_next

parse_tuples:
    push rcx
    call get_hex
    pop rcx
    mov [rbx], al
    inc rbx
    loop parse_tuples

parse_img_next:
    dec r15d
    jmp parse_images

parse_done:
    # Reinicia o ponteiro para ler o buffer binário preenchido
    lea rsi, [rip + buffer_in]        

    # Extrai a paleta de cores para o buffer dedicado
    lea rdi, [rip + palette]
    mov ecx, 16
    rep movsb                   

    # Lê a quantidade total de imagens
    movzx r15, byte ptr [rsi]
    inc rsi

image_loop:
    test r15, r15               
    jz finalize
    
    # Lê a quantidade de tuplas da imagem atual e salva a posição base
    movzx r12, byte ptr [rsi]
    inc rsi
    mov r14, rsi                

    # Calcula largura e altura máximas iterando pelas tuplas
    xor r8, r8                  
    xor r9, r9                  
    mov rcx, r12                
scan_loop:
    test rcx, rcx
    jz end_scan
    
    movzx eax, byte ptr [rsi]   
    cmp eax, r8d
    cmovg r8d, eax              
    
    movzx eax, byte ptr [rsi+1] 
    cmp eax, r9d
    cmovg r9d, eax              
    
    add rsi, 3                  
    dec rcx
    jmp scan_loop
end_scan:
    inc r8d                     
    inc r9d                     

    # Calcula a taxa de compressão (%)
    mov eax, r12d               
    imul eax, 300               
    mov ecx, r8d
    imul ecx, r9d               
    xor edx, edx
    div ecx                     
    mov r13d, eax               

    # Escreve o cabeçalho de taxa no arquivo de saída
    push r8                     
    push r9

    mov rax, 1                  
    mov rdi, [rip + fd_out]           
    lea rsi, [rip + msg_bracket1]
    mov rdx, 1
    syscall

    mov eax, r13d               
    mov ebx, 10
    lea rdi, [rip + num_str + 31]
    mov byte ptr [rdi], 0       
conv_taxa:
    xor edx, edx
    div ebx
    add dl, '0'                 
    dec rdi
    mov [rdi], dl
    test eax, eax
    jnz conv_taxa
    
    mov rsi, rdi
    lea rdx, [rip + num_str + 31]
    sub rdx, rdi                
    mov rax, 1
    mov rdi, [rip + fd_out]
    syscall

    mov rax, 1
    mov rdi, [rip + fd_out]
    lea rsi, [rip + msg_bracket2]
    mov rdx, 3
    syscall

    pop r9                      
    pop r8                      

    # Limpa o buffer da imagem preenchendo com espaços em branco
    mov ecx, r8d
    imul ecx, r9d
    lea rdi, [rip + image_buf]
    mov al, ' '
    rep stosb

    # Renderiza a imagem decodificando o RLE
    mov rsi, r14                
    mov rcx, r12                
render_loop:
    test rcx, rcx
    jz end_render

    movzx eax, byte ptr [rsi]   
    movzx ebx, byte ptr [rsi+1] 
    movzx edx, byte ptr [rsi+2] 

    mov edi, edx
    shr edi, 4                  
    and edx, 0x0F               
    
    lea rbp, [rip + palette]
    mov r10b, byte ptr [rbp + rdx] 

    imul ebx, r8d               
    add ebx, eax                
    lea r11, [rip + image_buf]  
    
fill_loop:
    test edi, edi               
    jz end_fill
    mov byte ptr [r11 + rbx], r10b  
    inc ebx
    dec edi
    jmp fill_loop
end_fill:

    add rsi, 3                  
    dec rcx
    jmp render_loop
end_render:

    # Escreve a imagem renderizada no arquivo de saída, linha por linha
    lea rsi, [rip + image_buf]
    mov rcx, r9                 
print_lines:
    test rcx, rcx
    jz next_image

    push rcx
    
    mov rax, 1
    mov rdi, [rip + fd_out]
    mov rdx, r8                 
    syscall
    
    push rsi
    mov rax, 1
    mov rdi, [rip + fd_out]
    lea rsi, [rip + msg_newline]
    mov rdx, 1
    syscall
    pop rsi

    add rsi, r8                 
    pop rcx
    dec rcx
    jmp print_lines

next_image:
    mov eax, r12d
    imul eax, 3
    add r14, rax                
    mov rsi, r14
    dec r15                     
    jmp image_loop

finalize:
    # Fecha o arquivo de entrada
    mov rax, 3                  
    mov rdi, [rip + fd_in]
    syscall
    
    # Fecha o arquivo de saída
    mov rax, 3
    mov rdi, [rip + fd_out]
    syscall

exit_program:
    mov rax, 60                 
    xor rdi, rdi                
    syscall

exit_error:
    mov rax, 60
    mov rdi, 1                  
    syscall


# Parser de Texto para Hexadecimal
get_hex:
    mov rsi, [rip + text_ptr]
    xor eax, eax

.skip_ws_h:
    movzx edx, byte ptr [rsi]
    inc rsi
    test dl, dl
    jz .done_h
    cmp dl, 32
    jle .skip_ws_h
    dec rsi

.read_h:
    movzx edx, byte ptr [rsi]
    cmp dl, 32
    jle .done_h          
    inc rsi

    sub dl, '0'          
    cmp dl, 9
    jbe .acc_h           

    and dl, 0xDF         
    sub dl, 7           

.acc_h:
    shl eax, 4           
    add eax, edx
    jmp .read_h

.done_h:
    mov [rip + text_ptr], rsi
    ret


# Parser de Texto para Decimal
get_dec:
    mov rsi, [rip + text_ptr]
    xor eax, eax

.skip_ws_d:
    movzx edx, byte ptr [rsi]
    inc rsi
    test dl, dl
    jz .done_d
    cmp dl, 32
    jle .skip_ws_d
    dec rsi

.read_d:
    movzx edx, byte ptr [rsi]
    test dl, dl
    jz .done_d
    cmp dl, 32
    jle .done_d
    inc rsi
    
    sub dl, '0'
    imul eax, 10           
    add eax, edx
    jmp .read_d

.done_d:
    mov [rip + text_ptr], rsi
    ret
    