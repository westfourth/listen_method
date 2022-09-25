# listen_method观察器

## 使用说明

### 接口

```objc
/**
    监听实例方法调用
 
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
```

### 举例

`ClassA`想要监听`ClassB`的`increase:`方法

```objc
//	ClassA
@property id block;

//	ClassB
- (int)increase:(int)num {
    return ++num;
}
```

**监听**

```objc
    self.block = ^void(id obj, int num) {
        puts(__func__);
    };
    listen_method(ClassB, @selector(increase:), self.block);
```

**触发**

```objc
    int a = [self increase:self.num];
```

**释放**

```objc
    listen_method_remove(ClassB, @selector(increase:), self.block);
```

## 原理

向被监听的方法中插入代码

```objc
- (int)increase:(int)num {
	// 原来的实现
	...
	int result = ...
	
	//	插入的代码
	for (id block in blockArray) {
		block(name);
	}
	
	return result;
}
```

### 设计
>
1. 使用一个`BOOL`类型的`class property`标记该setter方法是否插入过代码。
1. 如果未插入过代码，则插入代码，并将该标记置为`YES`
1. 取出该`class `关联的`block`数组，依次调用。

**调用约定**

插入代码的时候，需要构建一个新方法，在新方法中调用原来的方法，并一次执行block。其中方法的参数、类型、顺序和返回值类型都不一样，这里就涉及到**调用约定**。
>
1. 通过`libffi`创建一个函数原型，这个函数原型的参数、类型、顺序和返回值类型与需要修改的方法的参数、类型、顺序和返回值类型完全一致。
1. 执行该方法是，会触发函数原型绑定的绑定函数，绑定函数中有参数值、返回值地址。
1. 有了参数值、返回值地址，通过`libffi`调用该方法原来的`imp`。
1. 在通过`block`构建一个新的`imp1`，再次使用`libffi`调用该`imp1`