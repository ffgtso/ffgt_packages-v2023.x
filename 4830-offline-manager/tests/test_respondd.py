"""Compile and execute the actual responder with host UCI/JSON API doubles.
This verifies enabled-state semantics, not target-library ABI integration.
"""
import pathlib
import subprocess
import tempfile
import unittest

class ResponddTest(unittest.TestCase):
    def test_effective_enabled_state(self):
        source = (pathlib.Path(__file__).resolve().parents[1] / 'src/respondd.c')
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / 'json-c').mkdir()
            (root / 'respondd.h').write_text('struct json_object; struct respondd_provider_info {const char *name; struct json_object *(*provider)(void);};\n')
            (root / 'json-c/json.h').write_text('struct json_object {int value;}; struct json_object *json_object_new_object(void); struct json_object *json_object_new_boolean(int); void json_object_object_add(struct json_object *,const char *,struct json_object *);\n')
            (root / 'uci.h').write_text('''
#define UCI_FLAG_STRICT 1
struct uci_context {int flags;}; struct uci_package {int id;}; struct uci_section {int id;};
struct uci_context *uci_alloc_context(void); void uci_free_context(struct uci_context *);
int uci_load(struct uci_context *,const char *,struct uci_package **);
struct uci_section *uci_lookup_section(struct uci_context *,struct uci_package *,const char *);
const char *uci_lookup_option_string(struct uci_context *,struct uci_section *,const char *);
''')
            harness = r'''
#include <assert.h>
#include "respondd.c"
static int mask, failure, reported, freed;
static const char *truth="1";
struct uci_context *uci_alloc_context(void){static struct uci_context c;return failure==1?NULL:&c;}
void uci_free_context(struct uci_context *c){assert(c);freed++;}
int uci_load(struct uci_context *c,const char *name,struct uci_package **p){
 static struct uci_package a={0},b={1};(void)c;
 if(failure==2)return 1;*p=!strcmp(name,"autoupdater")?&b:&a;return 0;
}
struct uci_section *uci_lookup_section(struct uci_context *c,struct uci_package *p,const char *name){
 static struct uci_section s[2]={{0},{1}};(void)c;assert(!strcmp(name,"settings"));return failure==3?NULL:&s[p->id];
}
const char *uci_lookup_option_string(struct uci_context *c,struct uci_section *s,const char *key){
 (void)c;int bit=s->id?4:(!strcmp(key,"enabled")?1:2);return failure==4?NULL:((mask&bit)?truth:"0");
}
struct json_object *json_object_new_object(void){static struct json_object o;return &o;}
struct json_object *json_object_new_boolean(int value){static struct json_object o;o.value=value;return &o;}
void json_object_object_add(struct json_object *o,const char *key,struct json_object *v){(void)o;if(!strcmp(key,"wifi-fallback"))reported=v->value;}
int main(void){
 const char *values[]={"1","true","yes","on"};
 for(int i=0;i<4;i++){truth=values[i];for(mask=0;mask<8;mask++){reported=-1;respondd_provider_nodeinfo();assert(reported==(mask==7));}}
 mask=7;for(failure=1;failure<=4;failure++){reported=-1;respondd_provider_nodeinfo();assert(reported==0);}
 assert(freed==35);return 0;
}
'''
            (root / 'respondd.c').write_bytes(source.read_bytes())
            (root / 'test.c').write_text(harness)
            exe = root / 'test'
            subprocess.run(['cc', '-std=c99', '-Wall', '-Wextra', '-Werror', '-Wno-misleading-indentation', '-I', str(root), str(root/'test.c'), '-o', str(exe)], check=True)
            subprocess.run([str(exe)], check=True)

if __name__ == '__main__':
    unittest.main()
