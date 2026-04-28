# gera_teste.py
# Script para gerar uma entrada válida com tamanho máximo (255x255)

paleta = "2E 27 22 3A 2D 3D 2B 2A 7C 4C 5A 4D 2A 23 25 40\n"
num_imagens = "1\n"

# Vamos preencher a imagem de 255x255.
# Como cada tupla desenha até 14 pixels (Length max é 14), 
# precisamos de cerca de 18 tuplas por linha para cobrir 255 pixels de largura.
# Total de tuplas: ~18 tuplas/linha * 255 linhas = 4590 tuplas.

tuplas = []
for y in range(255):
    for x_base in range(0, 255, 14):
        x = x_base
        length = 14
        
        # Ajusta o length se passar de 255 no total
        if x + length > 255:
            length = 255 - x
            
        # Garante length mínimo de 1 para ser válido
        if length <= 0:
            continue

        # Alterna cores da paleta (índices 1 e 2) baseada na linha e coluna
        color_index = 1 if (x_base // 14 + y) % 2 == 0 else 2
        
        # Estrutura Color_Length: High 4 bits = Length, Low 4 bits = Color
        color_length = (length << 4) | (color_index & 0x0F)
        
        # Formata a tupla: XX YY CL
        tuplas.append(f"{x:02X} {y:02X} {color_length:02X}")

num_tuplas = f"{len(tuplas)}\n"
dados_tuplas = " ".join(tuplas) + "\n"

with open("entrada_gigante_limite.txt", "w") as f:
    f.write(paleta)
    f.write(num_imagens)
    f.write(num_tuplas)
    f.write(dados_tuplas)
    
print(f"Arquivo de teste entrada_gigante_limite.txt gerado com sucesso!")
print(f"Ele contém 1 imagem de 255x255 pixels definida por {len(tuplas)} tuplas.")
