// ChabahRoot -- Programme eBPF de capture d'evenements
// Capture des appels systeme critiques: execve, setuid, capability changes
// Architecture: filtres in-kernel avec ring buffer pour communication user-space

#include <linux/bpf.h>
#include <linux/ptrace.h>
#include <linux/sched.h>
#include <uapi/linux/eventfd.h>

// Event structure partagee kernel-userspace
struct event {
    __u32 pid;
    __u32 ppid;
    __u32 uid;
    __u32 gid;
    __u64 ts;
    char comm[16];
    char argv[256];
    __u32 event_type;  // 1=exec, 2=setuid, 3=setgid, 4=prctl
};

// Macro de section pour eBPF
#define SEC(NAME) __attribute__((section(NAME), used))

// Declaration du ring buffer pour streaming d'evenements
char _license[] SEC("license") = "GPL";

// Ring buffer pour transfert vers user-space
struct {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 256 * 1024);
} events SEC(".maps");

// Map pour tracer les PIDs deja detectes (evite le spam)
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    type_key = __u32;
    type_value = __u64;
    __uint(max_entries, 10240);
} seen_pids SEC(".maps");

// Probe sur sys_enter_execve: capture des executions de binaires
SEC("tracepoint/syscalls/sys_enter_execve")
int trace_exec(struct trace_event_raw_sys_enter *ctx) {
    struct event *e;
    
    // Allouer un evenement dans le ring buffer
    e = bpf_ringbuf_reserve(&events, sizeof(*e), 0);
    if (!e)
        return 0;
    
    // Recuperer les informations de base du processus
    __u64 uid_gid = bpf_get_current_uid_gid();
    e->uid = uid_gid & 0xFFFFFFFF;
    e->gid = uid_gid >> 32;
    e->pid = bpf_get_current_pid_tgid() & 0xFFFFFFFF;
    e->ppid = bpf_get_current_pid_tgid() >> 32;
    e->ts = bpf_ktime_get_ns();
    e->event_type = 1;  // exec
    
    // Recuperer le nom du processus
    bpf_get_current_comm(&e->comm, sizeof(e->comm));
    
    // Extraire le premier argument (nom du binaire)
    bpf_probe_read_user_str(&e->argv, sizeof(e->argv),
        (void *)ctx->args[0]);
    
    // Transferer l'evenement vers user-space
    bpf_ringbuf_submit(e, 0);
    
    return 0;
}

// Probe sur sys_enter_setuid: detecte les escalades d'UID
SEC("tracepoint/syscalls/sys_enter_setuid")
int trace_setuid(struct trace_event_raw_sys_enter *ctx) {
    struct event *e;
    __u32 target_uid = ctx->args[0];
    
    e = bpf_ringbuf_reserve(&events, sizeof(*e), 0);
    if (!e)
        return 0;
    
    __u64 uid_gid = bpf_get_current_uid_gid();
    e->uid = uid_gid & 0xFFFFFFFF;
    e->gid = uid_gid >> 32;
    e->pid = bpf_get_current_pid_tgid() & 0xFFFFFFFF;
    e->ppid = bpf_get_current_pid_tgid() >> 32;
    e->ts = bpf_ktime_get_ns();
    e->event_type = 2;  // setuid
    
    bpf_get_current_comm(&e->comm, sizeof(e->comm));
    
    // Enregistrer le UID cible
    bpf_snprintf(e->argv, sizeof(e->argv), "setuid(%u)", target_uid);
    
    bpf_ringbuf_submit(e, 0);
    
    return 0;
}

// Probe sur sys_enter_setgid: detecte les escalades de GID
SEC("tracepoint/syscalls/sys_enter_setgid")
int trace_setgid(struct trace_event_raw_sys_enter *ctx) {
    struct event *e;
    __u32 target_gid = ctx->args[0];
    
    e = bpf_ringbuf_reserve(&events, sizeof(*e), 0);
    if (!e)
        return 0;
    
    __u64 uid_gid = bpf_get_current_uid_gid();
    e->uid = uid_gid & 0xFFFFFFFF;
    e->gid = uid_gid >> 32;
    e->pid = bpf_get_current_pid_tgid() & 0xFFFFFFFF;
    e->ppid = bpf_get_current_pid_tgid() >> 32;
    e->ts = bpf_ktime_get_ns();
    e->event_type = 3;  // setgid
    
    bpf_get_current_comm(&e->comm, sizeof(e->comm));
    
    // Enregistrer le GID cible
    bpf_snprintf(e->argv, sizeof(e->argv), "setgid(%u)", target_gid);
    
    bpf_ringbuf_submit(e, 0);
    
    return 0;
}

// Probe sur sys_enter_prctl: detecte les changements de capabilities
SEC("tracepoint/syscalls/sys_enter_prctl")
int trace_prctl(struct trace_event_raw_sys_enter *ctx) {
    struct event *e;
    __u32 option = ctx->args[0];
    
    // Filtrer seulement les appels pertinents pour les capabilities
    if (option != 15)  // PR_SET_SECUREBITS
        return 0;
    
    e = bpf_ringbuf_reserve(&events, sizeof(*e), 0);
    if (!e)
        return 0;
    
    __u64 uid_gid = bpf_get_current_uid_gid();
    e->uid = uid_gid & 0xFFFFFFFF;
    e->gid = uid_gid >> 32;
    e->pid = bpf_get_current_pid_tgid() & 0xFFFFFFFF;
    e->ppid = bpf_get_current_pid_tgid() >> 32;
    e->ts = bpf_ktime_get_ns();
    e->event_type = 4;  // prctl
    
    bpf_get_current_comm(&e->comm, sizeof(e->comm));
    bpf_snprintf(e->argv, sizeof(e->argv), "prctl(option=%u)", option);
    
    bpf_ringbuf_submit(e, 0);
    
    return 0;
}
