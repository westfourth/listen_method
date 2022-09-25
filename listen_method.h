//
//  listen_method.h
//  PromiseKit
//
//  Created by xisi on 2022/9/10.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


/**
    监听实例方法调用

    @param block       原型为：void (^)(id obj, ...)，obj不仅仅可以为id、Class、SEL类型（block也属于id类型），
                    也可以为C语言基本类型（char, int, long, float, double......BOOL），以及char*、void*，
                    不可以为struct、union、C语言数组（例如：char[12]）
    @code
        //  方法
        - (NSUInteger)insertObject:(id)anObject atIndex:(NSUInteger)index;
        //  对应的block：无返回值、无SEL
        ^void(id obj, id anObject, NSUInteger index)
        //  对应的block：有返回值（返回值也会被忽略）、无SEL
        ^NSUInteger(id obj, id anObject, NSUInteger index)
    @endcode

    @note  cls持有block，需要调用 \c listen_method_remove() 释放。
 
    @note   block   会被调用，并且block没有返回值（即时有返回值也会被忽略）
 */
void listen_method(Class cls, SEL sel, id block);


/**
    移除监听实例方法调用
 
    @note   block   不会被调用
 */
void listen_method_remove(Class cls, SEL sel, id block);


/**
    获取监听的blocks
 */
NSMutableArray* _Nullable listen_method_blocks(id obj, SEL sel);


NS_ASSUME_NONNULL_END
