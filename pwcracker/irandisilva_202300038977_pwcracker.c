#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <pthread.h>

typedef struct {
    char login[64];
    uint8_t target_hash[8];
    char password_found[8];
} ThreadData;

// Hash MAO-64 Thread-Safe
void MAO_64_safe(uint8_t* hash, const char* senha) {
    uint32_t i, n = strlen(senha), nr = 32, seed = 0;
    
    for(i = 0; i < n; i++) {
        seed = (seed << 8) | ((seed >> 24) ^ senha[i]);
    }
    
    uint32_t local_ri = seed; 
    
    for(i = 0; i < 8; i++) hash[i] = 0;
    
    for(i = 0; i < nr; i++) {
        uint8_t* p = (uint8_t*)(&local_ri);
        local_ri = (1103515245 * local_ri) + 12345;
        uint8_t hrand_val = p[0] ^ p[1] ^ p[2] ^ p[3];
        
        hash[i & 0b111] = hash[i & 0b111] ^ hrand_val;
    }
}

// Hex para binario
void hex2bin(const char* hex, uint8_t* bin) {
    for(int i = 0; i < 8; i++) {
        sscanf(hex + 2*i, "%2hhx", &bin[i]);
    }
}

// Compara hash
int compare_hash(uint8_t* h1, uint8_t* h2) {
    for(int i = 0; i < 8; i++) {
        if(h1[i] != h2[i]) return 0;
    }
    return 1;
}

// Tarefa da thread (Forca Bruta)
void* crack_password(void* arg) {
    ThreadData* data = (ThreadData*)arg;
    
    const char charset[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    int num_chars = strlen(charset);
    
    char guess[5];
    uint8_t current_hash[8];
    
    // Tamanho 2
    for(int i = 0; i < num_chars; i++) {
        for(int j = 0; j < num_chars; j++) {
            guess[0] = charset[i]; guess[1] = charset[j]; guess[2] = '\0';
            MAO_64_safe(current_hash, guess);
            if(compare_hash(current_hash, data->target_hash)) {
                strcpy(data->password_found, guess);
                return NULL;
            }
        }
    }
    
    // Tamanho 3
    for(int i = 0; i < num_chars; i++) {
        for(int j = 0; j < num_chars; j++) {
            for(int k = 0; k < num_chars; k++) {
                guess[0] = charset[i]; guess[1] = charset[j]; guess[2] = charset[k]; guess[3] = '\0';
                MAO_64_safe(current_hash, guess);
                if(compare_hash(current_hash, data->target_hash)) {
                    strcpy(data->password_found, guess);
                    return NULL;
                }
            }
        }
    }
    
    // Tamanho 4
    for(int i = 0; i < num_chars; i++) {
        for(int j = 0; j < num_chars; j++) {
            for(int k = 0; k < num_chars; k++) {
                for(int l = 0; l < num_chars; l++) {
                    guess[0] = charset[i]; guess[1] = charset[j]; 
                    guess[2] = charset[k]; guess[3] = charset[l]; guess[4] = '\0';
                    MAO_64_safe(current_hash, guess);
                    if(compare_hash(current_hash, data->target_hash)) {
                        strcpy(data->password_found, guess);
                        return NULL;
                    }
                }
            }
        }
    }
    
    strcpy(data->password_found, "NOT_FOUND");
    return NULL;
}

int main(int argc, char* argv[]) {
    if (argc < 3) {
        printf("Quantidade de argumentos invalida.\n");
        return 1;
    }

    FILE* input = fopen(argv[1], "r");
    if (input == NULL) {
        printf("Erro ao abrir o arquivo de entrada.\n");
        return 1;
    }
    
    FILE* output = fopen(argv[2], "w");
    if (output == NULL) {
        printf("Erro ao abrir o arquivo de saida.\n");
        fclose(input);
        return 1;
    }

    int n;
    if (fscanf(input, "%d", &n) != 1) {
        fclose(input);
        fclose(output);
        return 1;
    }

    ThreadData* threads_data = malloc(n * sizeof(ThreadData));
    pthread_t* threads = malloc(n * sizeof(pthread_t));

    for(int i = 0; i < n; i++) {
        char line[256];
        fscanf(input, "%s", line);
        
        char* token = strtok(line, ":");
        strcpy(threads_data[i].login, token);
        
        token = strtok(NULL, ":");
        hex2bin(token, threads_data[i].target_hash);
    }

    for(int i = 0; i < n; i++) {
        pthread_create(&threads[i], NULL, crack_password, &threads_data[i]);
    }

    for(int i = 0; i < n; i++) {
        pthread_join(threads[i], NULL);
        fprintf(output, "%s:%s\n", threads_data[i].login, threads_data[i].password_found);
    }

    free(threads_data);
    free(threads);
    fclose(input);
    fclose(output);
    
    return 0;
}