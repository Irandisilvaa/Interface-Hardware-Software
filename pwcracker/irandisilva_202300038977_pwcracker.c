#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <pthread.h>

#define NUM_THREADS 4

typedef struct {
    char login[64];
    uint64_t target_hash_val; 
    char password_found[8];
    int original_index;
} Account;

typedef struct {
    Account** sorted_accounts;
    int num_accounts;
    int start_char_idx;
    int end_char_idx;
    uint8_t* quick_check; 
} WorkerData;

inline uint64_t finalize_hash(uint32_t seed) {
    uint32_t local_ri = seed; 
    uint64_t result_hash = 0; 
    uint8_t* hash = (uint8_t*)&result_hash;
    
    for(uint32_t i = 0; i < 32; i++) {
        local_ri = (1103515245 * local_ri) + 12345;
        uint8_t hrand_val = (local_ri ^ (local_ri >> 8) ^ (local_ri >> 16) ^ (local_ri >> 24)) & 0xFF;
        hash[i & 7] ^= hrand_val;
    }
    
    return result_hash;
}

void hex2bin_opt(const char* hex, uint64_t* bin_out) {
    uint8_t temp[8];
    for(int i = 0; i < 8; i++) {
        sscanf(hex + 2*i, "%2hhx", &temp[i]);
    }
    *bin_out = *(uint64_t*)temp;
}

// Retorna apenas o Índice onde achou, ou -1 se não achou
static inline int binary_search(Account** sorted, int n_accs, uint64_t hash_val) {
    int left = 0, right = n_accs - 1;
    while (left <= right) {
        int mid = left + (right - left) / 2;
        uint64_t mid_val = sorted[mid]->target_hash_val;
        if (mid_val == hash_val) return mid;
        if (mid_val < hash_val) left = mid + 1;
        else right = mid - 1;
    }
    return -1;
}

// Só monta a string da senha aqui, quando já sabemos que está certo!
static inline void assign_match(Account** sorted, int n_accs, int mid, uint64_t hash_val, const char* guess) {
    int i = mid;
    while(i >= 0 && sorted[i]->target_hash_val == hash_val) {
        if (sorted[i]->password_found[0] == '\0') strcpy(sorted[i]->password_found, guess);
        i--;
    }
    i = mid + 1;
    while(i < n_accs && sorted[i]->target_hash_val == hash_val) {
        if (sorted[i]->password_found[0] == '\0') strcpy(sorted[i]->password_found, guess);
        i++;
    }
}

int compare_accounts(const void* a, const void* b) {
    Account* acc_a = *(Account**)a;
    Account* acc_b = *(Account**)b;
    if (acc_a->target_hash_val < acc_b->target_hash_val) return -1;
    if (acc_a->target_hash_val > acc_b->target_hash_val) return 1;
    return 0;
}

void* crack_worker(void* arg) {
    WorkerData* wd = (WorkerData*)arg;
    const char charset[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    const int num_chars = 62;
    
    Account** sorted = wd->sorted_accounts;
    int n_accs = wd->num_accounts;
    uint8_t* qc = wd->quick_check; // Tabela de lookup em cache L1
    
    for(int i = wd->start_char_idx; i < wd->end_char_idx; i++) {
        uint32_t s1 = charset[i]; 
        
        for(int j = 0; j < num_chars; j++) {
            uint32_t s2 = (s1 << 8) | ((s1 >> 24) ^ charset[j]);
            uint64_t h2 = finalize_hash(s2);
            
            // Só entra na busca se a tabela autorizar
            if (qc[h2 & 0xFFFF]) {
                int idx = binary_search(sorted, n_accs, h2);
                if (idx != -1) {
                    char g[3] = {charset[i], charset[j], '\0'};
                    assign_match(sorted, n_accs, idx, h2, g);
                }
            }
            
            for(int k = 0; k < num_chars; k++) {
                uint32_t s3 = (s2 << 8) | ((s2 >> 24) ^ charset[k]);
                uint64_t h3 = finalize_hash(s3);
                
                if (qc[h3 & 0xFFFF]) {
                    int idx = binary_search(sorted, n_accs, h3);
                    if (idx != -1) {
                        char g[4] = {charset[i], charset[j], charset[k], '\0'};
                        assign_match(sorted, n_accs, idx, h3, g);
                    }
                }
                
                for(int l = 0; l < num_chars; l++) {
                    uint32_t s4 = (s3 << 8) | ((s3 >> 24) ^ charset[l]);
                    uint64_t h4 = finalize_hash(s4);
                    
                    // Pula 99.99% das buscas binárias!
                    if (qc[h4 & 0xFFFF]) {
                        int idx = binary_search(sorted, n_accs, h4);
                        if (idx != -1) {
                            char g[5] = {charset[i], charset[j], charset[k], charset[l], '\0'};
                            assign_match(sorted, n_accs, idx, h4, g);
                        }
                    }
                }
            }
        }
    }
    return NULL;
}

int main(int argc, char* argv[]) {
    if (argc < 3) return 1;

    FILE* input = fopen(argv[1], "r");
    FILE* output = fopen(argv[2], "w");
    if (!input || !output) return 1;

    int n;
    if (fscanf(input, "%d", &n) != 1) return 1;

    Account* accounts = malloc(n * sizeof(Account));
    Account** sorted_accounts = malloc(n * sizeof(Account*)); 
    
    // Aloca a Tabela Rápida 
    uint8_t* quick_check = calloc(65536, sizeof(uint8_t));

    for(int i = 0; i < n; i++) {
        char line[256];
        fscanf(input, "%s", line);
        
        char* token = strtok(line, ":");
        strcpy(accounts[i].login, token);
        
        token = strtok(NULL, ":");
        hex2bin_opt(token, &accounts[i].target_hash_val);
        
        accounts[i].original_index = i;
        accounts[i].password_found[0] = '\0'; 
        sorted_accounts[i] = &accounts[i];
        
        // Marca "1" na tabela usando os últimos 16 bits do Hash alvo
        quick_check[accounts[i].target_hash_val & 0xFFFF] = 1;
    }

    qsort(sorted_accounts, n, sizeof(Account*), compare_accounts);

    pthread_t threads[NUM_THREADS];
    WorkerData wdata[NUM_THREADS];
    
    int chars_per_thread = 62 / NUM_THREADS;
    int remainder = 62 % NUM_THREADS;
    int current_start = 0;

    for(int i = 0; i < NUM_THREADS; i++) {
        wdata[i].sorted_accounts = sorted_accounts;
        wdata[i].num_accounts = n;
        wdata[i].start_char_idx = current_start;
        wdata[i].end_char_idx = current_start + chars_per_thread + ((i < remainder) ? 1 : 0);
        wdata[i].quick_check = quick_check; // Passa o filtro para as threads
        current_start = wdata[i].end_char_idx;

        pthread_create(&threads[i], NULL, crack_worker, &wdata[i]);
    }

    for(int i = 0; i < NUM_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }

    for(int i = 0; i < n; i++) {
        if (accounts[i].password_found[0] == '\0') {
            fprintf(output, "%s:NOT_FOUND\n", accounts[i].login);
        } else {
            fprintf(output, "%s:%s\n", accounts[i].login, accounts[i].password_found);
        }
    }

    free(accounts);
    free(sorted_accounts);
    free(quick_check);
    fclose(input);
    fclose(output);
    
    return 0;
}
