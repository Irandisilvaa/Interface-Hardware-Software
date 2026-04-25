.intel_syntax noprefix
.global _start

#  Buffers de memória
.section .bss
    text_buffer: .space 65536    #  Buffer para ler o arquivo .txt puro
    text_ptr:    .quad 0         # Ponteiro de leitura do texto
    
    buffer_in:  .space 8192      # Buffer para a versão binária convertida
    palette:    .space 16        
    image_buf:  .space 8192      
    num_str:    .space 32        
    fd_in:      .quad 0          
    fd_out:     .quad 0          

#  Constantes
 
.section .data
    msg_bracket1: .ascii "["
    msg_bracket2: .ascii "%]\n"
    msg_newline:  .ascii "\n"

 
#  O Programa Principal
 
.section .text
_start:
  
    # ABRIR ARQUIVOS (ARGC e ARGV)
  
    mov r12, [rsp]              
    cmp r12, 3                  
    jl exit_error               

    # Abrir arquivo de ENTRADA
    mov rax, 2                  
    mov rdi, [rsp + 16]         
    mov rsi, 0                  
    syscall
    mov [fd_in], rax            

    # Abrir arquivo de SAÍDA
    mov rax, 2                  
    mov rdi, [rsp + 24]         
    mov rsi, 577                
    mov rdx, 0644               
    syscall
    mov [fd_out], rax           

  
    # LER O ARQUIVO DE TEXTO PARA A MEMÓRIA
  
    mov rax, 0                  
    mov rdi, [fd_in]            
    lea rsi, [text_buffer]      # <--- Lê para o buffer de texto
    mov rdx, 65536               
    syscall

  
    # PARSER: CONVERTER O TEXTO PARA BINÁRIO NO BUFFER_IN
  
    lea rsi, [text_buffer]
    mov [text_ptr], rsi
    lea rbx, [buffer_in]        # RBX vai apontar onde vamos escrever os bytes limpos

    # 1. Ler 16 bytes da paleta (Em HEXADECIMAL)
    mov rcx, 16
parse_pal:
    push rcx
    call get_hex
    pop rcx
    mov [rbx], al
    inc rbx
    loop parse_pal

    # 2. Ler número de imagens n (Em DECIMAL)
    call get_dec
    mov [rbx], al
    inc rbx
    mov r15d, eax               # R15D guarda a qtde de imagens para o parser

parse_images:
    test r15d, r15d
    jz parse_done

    # 3. Ler quantidade de tuplas m (Em DECIMAL)
    call get_dec
    mov [rbx], al
    inc rbx
    mov r12d, eax               # R12D = m

    # 4. Ler m * 3 bytes de tuplas (Em HEXADECIMAL)
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
    # UFA! Agora o buffer_in tem os bytes exatamente como no arquivo binário.
    # Colocamos o RSI nele e a velha lógica assume!
    lea rsi, [buffer_in]        

  
    # EXTRAIR A PALETA (16 Bytes)
  
    lea rdi, [palette]
    mov ecx, 16
    rep movsb                   

  
    # QUANTIDADE DE IMAGENS
  
    movzx r15, byte ptr [rsi]
    inc rsi

image_loop:
    test r15, r15               
    jz finalize
    
    # QUANTIDADE DE TUPLAS (m)
    movzx r12, byte ptr [rsi]
    inc rsi
    mov r14, rsi                

  
    # CALCULAR LARGURA E ALTURA
  
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

    # CALCULAR TAXA %
    mov eax, r12d               
    imul eax, 300               
    mov ecx, r8d
    imul ecx, r9d               
    xor edx, edx
    div ecx                     

    mov r13d, eax               # Salva a taxa 

    # ESCREVER CABEÇALHO NO ARQUIVO
    push r8                     
    push r9

    mov rax, 1                  
    mov rdi, [fd_out]           
    lea rsi, [msg_bracket1]
    mov rdx, 1
    syscall

    mov eax, r13d               
    mov ebx, 10
    lea rdi, [num_str + 31]
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
    lea rdx, [num_str + 31]
    sub rdx, rdi                
    mov rax, 1
    mov rdi, [fd_out]
    syscall

    mov rax, 1
    mov rdi, [fd_out]
    lea rsi, [msg_bracket2]
    mov rdx, 3
    syscall

    pop r9                      
    pop r8                      

    # DESENHAR IMAGEM RLE

    mov ecx, r8d
    imul ecx, r9d
    lea rdi, [image_buf]
    mov al, ' '
    rep stosb

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
    
    lea rbp, [palette]
    mov r10b, byte ptr [rbp + rdx] 

    imul ebx, r8d               
    add ebx, eax                
    
fill_loop:
    test edi, edi               
    jz end_fill
    mov byte ptr [image_buf + ebx], r10b
    inc ebx
    dec edi
    jmp fill_loop
end_fill:

    add rsi, 3                  
    dec rcx
    jmp render_loop
end_render:

    # ESCREVER IMAGEM NO ARQUIVO

    lea rsi, [image_buf]
    mov rcx, r9                 
print_lines:
    test rcx, rcx
    jz next_image

    push rcx
    
    mov rax, 1
    mov rdi, [fd_out]
    mov rdx, r8                 
    syscall
    
    push rsi
    mov rax, 1
    mov rdi, [fd_out]
    lea rsi, [msg_newline]
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
    mov rax, 3                  
    mov rdi, [fd_in]
    syscall
    
    mov rax, 3
    mov rdi, [fd_out]
    syscall

exit_program:
    mov rax, 60                 
    xor rdi, rdi                
    syscall

exit_error:
    mov rax, 60
    mov rdi, 1                  
    syscall


 
# TRADUÇÃO TEXTO -> BINÁRIO
 

get_hex:
    mov rsi, [text_ptr]
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
    jle .done_h          # Se for espaço/quebra de linha, terminou o número
    inc rsi

    sub dl, '0'          # Tática ninja: assume logo de cara que é número (0-9)
    cmp dl, 9
    jbe .acc_h           # Se for entre 0 e 9, vai DIRETO acumular! Nada de saltos extras.

    # Se a CPU chegou aqui, é porque é letra (a-f ou A-F)
    and dl, 0xDF         # Converte minúscula para maiúscula
    sub dl, 7           

.acc_h:
    shl eax, 4           # Multiplica por 16
    add eax, edx
    jmp .read_h

.done_h:
    mov [text_ptr], rsi
    ret


get_dec:
    mov rsi, [text_ptr]
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
    imul eax, 10           # Multiplica por 10
    add eax, edx
    jmp .read_d
.done_d:
    mov [text_ptr], rsi
    ret