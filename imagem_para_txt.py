from PIL import Image
import sys

def converter_imagem(caminho_imagem, caminho_saida):
    try:
        # Abre a imagem e converte para tons de cinza (L)
        img = Image.open(caminho_imagem).convert('L')
    except Exception as e:
        print(f"Erro ao abrir a imagem: {e}")
        return

    # O seu Assembly suporta até 255x255 (pois X e Y usam 1 byte: 00 a FF)
    # Vamos redimensionar mantendo a proporção. 
    # Dica: coloquei largura max de 100 para caber legal no terminal sem quebrar a linha.
    img.thumbnail((120, 120))
    width, height = img.size

    # A sua paleta (do mais claro para o mais escuro)
    # . ' " : - = + * | L Z M * # % @
    paleta_hex = "2E 27 22 3A 2D 3D 2B 2A 7C 4C 5A 4D 2A 23 25 40"

    tuplas = []
    
    # Varre a imagem linha por linha
    for y in range(height):
        x = 0
        while x < width:
            # Pega o tom de cinza (0 a 255)
            pixel = img.getpixel((x, y))
            
            # Mapeia 0 (Preto) para índice 15 (@) e 255 (Branco) para índice 0 (.)
            color_index = 15 - int((pixel / 255.0) * 15)

            # Encontra quantos pixels seguidos têm a mesma cor (compressão RLE)
            length = 1
            # O tamanho máximo do chunk é 15, pois o Length usa apenas 4 bits (1111 em binário = 15)
            while x + length < width and length < 15:
                proximo_pixel = img.getpixel((x + length, y))
                proxima_cor = 15 - int((proximo_pixel / 255.0) * 15)
                if proxima_cor == color_index:
                    length += 1
                else:
                    break

            # Junta o Length (4 bits altos) com a Cor (4 bits baixos)
            color_length = (length << 4) | color_index
            
            # Adiciona a tupla: XX YY CL
            tuplas.append(f"{x:02X} {y:02X} {color_length:02X}")
            
            # Avança o X
            x += length

    # Salva no arquivo no seu formato customizado
    with open(caminho_saida, "w") as f:
        f.write(paleta_hex + "\n")
        f.write("1\n") # 1 imagem
        f.write(f"{len(tuplas)}\n")
        f.write(" ".join(tuplas) + "\n")

    print(f"Sucesso! Imagem redimensionada para {width}x{height}.")
    print(f"Gerado: {caminho_saida} com {len(tuplas)} tuplas de compressão.")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Uso: python imagem_para_txt.py <imagem_real.png> <saida.txt>")
    else:
        converter_imagem(sys.argv[1], sys.argv[2])