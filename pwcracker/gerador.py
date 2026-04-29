import random
import string

def mao_64_hash(senha):
    seed = 0
    for char in senha:
        val = ord(char)
        # Simula o comportamento de uint32_t em C
        seed = ((seed << 8) & 0xFFFFFFFF) | (((seed >> 24) ^ val) & 0xFF)
    
    local_ri = seed & 0xFFFFFFFF
    hash_arr = [0] * 8
    for i in range(32):
        local_ri = (1103515245 * local_ri + 12345) & 0xFFFFFFFF
        # XOR dos 4 bytes do uint32_t
        b0 = local_ri & 0xFF
        b1 = (local_ri >> 8) & 0xFF
        b2 = (local_ri >> 16) & 0xFF
        b3 = (local_ri >> 24) & 0xFF
        hrand_val = b0 ^ b1 ^ b2 ^ b3
        hash_arr[i & 0x7] ^= hrand_val
    
    return "".join(f"{b:02x}" for b in hash_arr)

charset = string.ascii_letters + string.digits
num_contas = 1000

with open("entrada.txt", "w") as f:
    f.write(f"{num_contas}\n")
    for i in range(num_contas):
        login = f"user_{i}"
        # Gera senha aleatória de 2 a 4 caracteres
        tamanho = random.randint(2, 4)
        senha = "".join(random.choice(charset) for _ in range(tamanho))
        hash_str = mao_64_hash(senha)
        f.write(f"{login}:{hash_str}\n")

print(f"Arquivo entrada.txt gerado com {num_contas} contas.")