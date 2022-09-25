//
//  listen_method.m
//  PromiseKit
//
//  Created by xisi on 2022/9/10.
//

#import "listen_method.h"
#import <objc/runtime.h>
#import <objc/objc-sync.h>
#include <ffi.h>

typedef struct listen_method_info {
    ffi_closure *closure;   //  can't be freed
    ffi_cif *cif;           //  can't be freed
    Class cls;
    SEL sel;                //  method selector
    IMP imp0;               //  method original imp
} listen_method_info;


//MARK: -   属性

//  关联对象的key
static SEL sel_for_bool(SEL sel) {
    const char *name = sel_getName(sel);
    NSString *key = [NSString stringWithFormat:@"listen_method_bool-%s", name];
    SEL keySEL = sel_registerName(key.UTF8String);
    return keySEL;
}

//  关联对象的key
static SEL sel_for_array(SEL sel) {
    const char *name = sel_getName(sel);
    NSString *key = [NSString stringWithFormat:@"listen_method_array-%s", name];
    SEL keySEL = sel_registerName(key.UTF8String);
    return keySEL;
}

//  类属性getter
static BOOL class_get_bool(Class cls, SEL sel) {
    SEL keySEL = sel_for_bool(sel);
    return [objc_getAssociatedObject(cls, keySEL) boolValue];
}

//  类属性setter
static void class_set_bool(Class cls, SEL sel, BOOL flag) {
    SEL keySEL = sel_for_bool(sel);
    objc_setAssociatedObject(cls, keySEL, @(flag), OBJC_ASSOCIATION_ASSIGN);
}

//  属性getter
static NSMutableArray* _Nullable class_get_array(id obj, SEL sel) {
    SEL keySEL = sel_for_array(sel);
    return objc_getAssociatedObject(obj, keySEL);
}

//  属性setter
static void class_set_array(id obj, SEL sel, NSMutableArray* _Nullable array) {
    SEL keySEL = sel_for_array(sel);
    objc_setAssociatedObject(obj, keySEL, array, OBJC_ASSOCIATION_RETAIN);
}


//MARK: -   libffi

static ffi_type* ffi_type_for_type(char ch) {
    switch (ch) {
        case _C_CHR:
            return &ffi_type_sint8;
            break;
        case _C_UCHR:
            return &ffi_type_uint8;
            break;
        case _C_SHT:
            return &ffi_type_sint16;
            break;
        case _C_USHT:
            return &ffi_type_uint16;
            break;
        case _C_INT:
            return &ffi_type_sint32;
            break;
        case _C_UINT:
            return &ffi_type_uint32;
            break;
        case _C_LNG:
            return &ffi_type_sint64;
            break;
        case _C_ULNG:
            return &ffi_type_uint64;
            break;
        case _C_LNG_LNG:
            return &ffi_type_sint64;
            break;
        case _C_ULNG_LNG:
            return &ffi_type_uint64;
            break;
        case _C_FLT:
            return &ffi_type_float;
            break;
        case _C_DBL:
            return &ffi_type_double;
            break;
        case _C_BOOL:
            return &ffi_type_sint8;
            break;
        case _C_ID:
            return &ffi_type_pointer;
            break;
        case _C_CLASS:
            return &ffi_type_pointer;
            break;
        case _C_SEL:
            return &ffi_type_pointer;
            break;
        case _C_CHARPTR:
            return &ffi_type_pointer;
            break;
        case _C_PTR:
            return &ffi_type_pointer;
            break;
        case _C_VOID:
            return &ffi_type_void;
            break;
        default:
            printf(">>> 不支持此类型（包括struct、union）\n");
            assert(0);
            break;
    }
    return &ffi_type_pointer;
}


//MARK: -   核心部分

//  调用block
static void call_block(ffi_cif *cif, void *ret, void **args, void *user_data) {
    listen_method_info *info = user_data;
    Class cls = info->cls;
    SEL sel = info->sel;
    
    //  生成函数原型
    ffi_status status = ffi_prep_cif(cif, FFI_DEFAULT_ABI, info->cif->nargs, info->cif->rtype, info->cif->arg_types);
    if (status == FFI_OK) {
        //  调用的block
        NSMutableArray *array = class_get_array(cls, sel);
        for (int i = 0; i < array.count; i++) {
            id block = array[i];
            IMP imp1 = imp_implementationWithBlock(block);
            //  调用block构成的imp，忽略返回值
            ffi_call(cif, imp1, NULL, args);
            imp_removeBlock(imp1);
        }
    }
}

//  函数实体
static void fun_binding(ffi_cif *cif, void *ret, void **args, void *user_data) {
    listen_method_info *info = user_data;
    Class cls = info->cls;
    SEL sel = info->sel;
    IMP imp0 = info->imp0;
    
    //  生成函数原型
    ffi_status status = ffi_prep_cif(cif, FFI_DEFAULT_ABI, info->cif->nargs, info->cif->rtype, info->cif->arg_types);
    if (status == FFI_OK) {
        //  调用原来的imp
        ffi_call(cif, imp0, ret, args);
    }
    
    //  调用block
    call_block(cif, ret, args, user_data);
}

//  向原有的setter方法中插入代码
static void class_inset_code(Class cls, SEL sel) {
    Method m = class_getInstanceMethod(cls, sel);
    IMP imp0 = method_getImplementation(m);
    
    //  声明一个函数指针
    void *fun;
    //  ⚠️⚠️closure 不可以被释放⚠️⚠️
    ffi_closure *closure = ffi_closure_alloc(sizeof(ffi_closure), &fun);
    if (closure) {
        //  ⚠️⚠️cif 不可以被释放⚠️⚠️
        ffi_cif *cif = calloc(1, sizeof(ffi_cif));
        
        //  参数个数
        unsigned nargs = method_getNumberOfArguments(m);
        
        //  返回值类型
        char *retType = method_copyReturnType(m);
        ffi_type *rtype = ffi_type_for_type(retType[0]);
        free(retType);

        //  各参数类型。    ⚠️⚠️atypes 不可以被释放⚠️⚠️
        ffi_type **atypes = calloc(nargs, sizeof(ffi_type *));
        for (int i = 0; i < nargs; i++) {
            char *argType = method_copyArgumentType(m, i);
            atypes[i] = ffi_type_for_type(argType[0]);
            free(argType);
        }
        
        //  生成函数原型
        ffi_status status = ffi_prep_cif(cif, FFI_DEFAULT_ABI, nargs, rtype, atypes);
        if (status == FFI_OK) {
            
            //  ⚠️⚠️info 不可以被释放⚠️⚠️
            listen_method_info *info = calloc(1, sizeof(listen_method_info));
            info->closure = closure;
            info->cif = cif;
            info->cls = cls;
            info->sel = sel;
            info->imp0 = imp0;
            
            //  生成一个函数指针，并把闭包和函数指针绑定到函数模版上
            status = ffi_prep_closure_loc(closure, cif, fun_binding, info, fun);
            if (status == FFI_OK) {
                //  设置为新的 IMP
                method_setImplementation(m, fun);
            }
        }
    }
}

//  监听方法调用
void listen_method(Class cls, SEL sel, id block) {
    objc_sync_enter(cls);
    //  查看该方法是否插入过代码片段
    BOOL flag = class_get_bool(cls, sel);
    if (flag == NO) {
        class_inset_code(cls, sel);
        class_set_bool(cls, sel, YES);
    }
    //  取出关联的array
    NSMutableArray *array = class_get_array(cls, sel);
    if (array == nil) {
        array = [NSMutableArray new];
        class_set_array(cls, sel, array);
    }
    //  添加到数组中
    [array addObject:block];
    objc_sync_exit(cls);
}

//  移除监听实例方法调用
void listen_method_remove(Class cls, SEL sel, id block) {
    objc_sync_enter(cls);
    //  取出关联的array
    NSMutableArray *array = class_get_array(cls, sel);
    //  从数组中移除
    [array removeObject:block];
    objc_sync_exit(cls);
}


NSMutableArray* _Nullable listen_method_blocks(id obj, SEL sel) {
    return class_get_array(obj, sel);
}
