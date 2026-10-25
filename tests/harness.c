#include "cpu.h"
#include <stdio.h>
#include <math.h>
#include <stdlib.h>

void sub_0048b1e0(CPU*); void sub_00631d30(CPU*); void sub_0050d2d0(CPU*);
void sub_0075dc4b(CPU*); void sub_0072b07b(CPU*); void sub_007420b0(CPU*);

/* temporary stub for a callee not lifted yet */
int g_stub_hits=0;
void sub_0061bce0(CPU *c){ g_stub_hits++; POP32(c->eip); }
void cpuid_shim(CPU*c){(void)c;}
uint64_t rdtsc_shim(void){return 0;}
void mem_commit(uint32_t,uint32_t);
void dispatch_indirect(CPU *c, uint32_t t){ fprintf(stderr,"indirect call 0x%08x unresolved\n",t); abort(); }

#define STACK_TOP 0x00F00000u
static CPU cpu;
static CPU *const c = &cpu;   /* the PUSH32/MR32 macros expect `c` */
static void reset(void){ memset(&cpu,0,sizeof cpu); cpu.esp=STACK_TOP; cpu.top=0; }

/* cdecl/stdcall call: push the arguments on the stack, put a return address, call, return eax */
static uint32_t call1(void(*fn)(CPU*), uint32_t a){
    reset(); PUSH32(a); PUSH32(0xDEADC0DEu); fn(&cpu); return cpu.eax;
}
static uint32_t call2(void(*fn)(CPU*), uint32_t a, uint32_t b){
    reset(); PUSH32(b); PUSH32(a); PUSH32(0xDEADC0DEu); fn(&cpu); return cpu.eax;
}
static uint32_t call_d(void(*fn)(CPU*), double d){
    reset(); uint64_t bits; memcpy(&bits,&d,8);
    PUSH32((uint32_t)(bits>>32)); PUSH32((uint32_t)bits); PUSH32(0xDEADC0DEu);
    fn(&cpu); return cpu.eax;
}

int pass=0, fail=0;
#define CHECK(name,got,exp) do{ uint32_t _g=(got),_e=(exp); \
    if(_g==_e){pass++; printf("  \033[32mPASS\033[0m  %-34s = 0x%08x\n",name,_g);} \
    else {fail++; printf("  \033[31mFAIL\033[0m  %-34s = 0x%08x (expected 0x%08x)\n",name,_g,_e);} }while(0)

int main(int argc,char**argv){
    const char*exe = argc>1?argv[1]:"SPEED2.EXE";
    mem_init();
    fprintf(stderr,"loading PE: %s\n",exe);
    if(mem_load_pe(exe)) return 1;
    mem_commit(0x00000000u, 0x01000000u);   /* test area + stack (including low addresses) */
    mem_fault_handler_install();
    fprintf(stderr,"guest memory base = %p\n\n", (void*)g_mem);

    printf("=== TEST 1: sub_0048b1e0  (array indexing: 0x832de0 + i*0x70) ===\n");
    for(uint32_t i=0;i<5;i++){
        char nm[64]; snprintf(nm,sizeof nm,"sub_0048b1e0(%u)",i);
        CHECK(nm, call1(sub_0048b1e0,i), 0x832de0u + i*0x70u);
    }
    CHECK("sub_0048b1e0(100)", call1(sub_0048b1e0,100), 0x832de0u + 100*0x70u);

    printf("\n=== TEST 2: sub_0075dc4b  (_finite(double) - IEEE754 exponent check) ===\n");
    struct { double v; const char*n; } dv[] = {
        {1.0,"1.0"},{0.0,"0.0"},{-3.14159,"-3.14159"},{1e300,"1e300"},
        {INFINITY,"+inf"},{-INFINITY,"-inf"},{NAN,"nan"},{1e-320,"1e-320 (subnormal)"}
    };
    for(unsigned k=0;k<sizeof dv/sizeof*dv;k++){
        char nm[64]; snprintf(nm,sizeof nm,"_finite(%s)",dv[k].n);
        /* reference: C isfinite() */
        CHECK(nm, call_d(sub_0075dc4b,dv[k].v), (uint32_t)(isfinite(dv[k].v)?1:0));
    }

    printf("\n=== TEST 3: sub_00631d30  (branching + stdcall 'ret 8' + subcall) ===\n");
    /* the range 0x61..0x68 -> returns 0 */
    CHECK("sub_00631d30(0x61,..)", call2(sub_00631d30,0x61,0), 0u);
    CHECK("sub_00631d30(0x65,..)", call2(sub_00631d30,0x65,0), 0u);
    CHECK("sub_00631d30(0x68,..)", call2(sub_00631d30,0x68,0), 0u);
    /* eax=0x19 -> reads [ecx+0x5f4]; ecx=0 => guest 0x5f4 */
    reset(); MR32(0x5f4u)=0xCAFEBABEu; PUSH32(0); PUSH32(0x19u); PUSH32(0xDEADC0DEu);
    cpu.ecx=0; sub_00631d30(&cpu);
    CHECK("sub_00631d30(0x19) -> [0x5f4]", cpu.eax, 0xCAFEBABEu);
    /* general path: swap and return the old value */
    reset(); cpu.ecx=0x00E00000u; MR32(0x00E00000u+2*4+0x590u)=0x11112222u;
    PUSH32(0x33334444u); PUSH32(2u); PUSH32(0xDEADC0DEu);
    sub_00631d30(&cpu);
    CHECK("swap: returns the old value", cpu.eax, 0x11112222u);
    CHECK("swap: new value written", MR32(0x00E00000u+2*4+0x590u), 0x33334444u);
    printf("  (sub-function stub called %d times)\n", g_stub_hits);

    printf("\n=== TEST 4: stack balance (stdcall cleanup) ===\n");
    reset(); PUSH32(0); PUSH32(0x61u); uint32_t sp_before=cpu.esp;
    PUSH32(0xDEADC0DEu); sub_00631d30(&cpu);
    CHECK("esp after ret 8", cpu.esp, sp_before + 8u);
    CHECK("return address in eip",  cpu.eip, 0xDEADC0DEu);

    printf("\n---------------------------------------------\n");
    printf("  PASS: %d    FAIL: %d\n", pass, fail);
    return fail?1:0;
}
