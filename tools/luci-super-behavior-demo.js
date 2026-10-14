'use strict';

/*
 * 最小复现：LuCI baseclass 的 super() 对"实例属性方法"与"类方法"的区别。
 * Class/super 的实现逐字搬运自 luci-base 的 luci.js。
 */

const toCamelCase = s => s.replace(/(?:^|[. -])(.)/g, (m0, m1) => m1.toUpperCase());
const superContext = {};
let classIndex = 0;

const Class = Object.assign(function() {}, {
	extend(properties) {
		const props = {
			__id__: { value: classIndex },
			__base__: { value: this.prototype },
			__name__: { value: properties.__name__ ?? `anonymous${classIndex++}` }
		};

		const ClassConstructor = function() {
			if (!(this instanceof ClassConstructor))
				throw new TypeError('Constructor must not be called without "new"');

			if (Object.getPrototypeOf(this).hasOwnProperty('__init__')) {
				if (typeof(this.__init__) != 'function')
					throw new TypeError('Class __init__ member is not a function');
				this.__init__.apply(this, arguments);
			}
			else {
				this.super('__init__', arguments);
			}
		};

		for (const key in properties)
			if (!props[key] && properties.hasOwnProperty(key))
				props[key] = { value: properties[key], writable: true };

		ClassConstructor.prototype = Object.create(this.prototype, props);
		ClassConstructor.prototype.constructor = ClassConstructor;
		Object.assign(ClassConstructor, this);
		ClassConstructor.displayName = toCamelCase(`${props.__name__.value}Class`);

		return ClassConstructor;
	},

	instantiate(args) {
		return new (this)(...args);
	},

	prototype: {
		super(key, ...callArgs) {
			if (key == null)
				return null;

			const slotIdx = `${this.__id__}.${key}`;
			const symStack = superContext[slotIdx];
			let protoCtx = null;

			for (protoCtx = Object.getPrototypeOf(symStack ? symStack[0] : Object.getPrototypeOf(this));
				 protoCtx != null && !protoCtx.hasOwnProperty(key);
				 protoCtx = Object.getPrototypeOf(protoCtx)) {}

			if (protoCtx == null)
				return null;

			let res = protoCtx[key];

			if (callArgs.length > 0) {
				if (typeof(res) != 'function')
					throw new ReferenceError(`${key} is not a function in base class`);

				if (Array.isArray(callArgs[0]) || (callArgs[0] && callArgs[0].callee))
					callArgs = callArgs[0];

				if (symStack)
					symStack.unshift(protoCtx);
				else
					superContext[slotIdx] = [ protoCtx ];

				res = res.apply(this, callArgs);

				if (symStack && symStack.length > 1)
					symStack.shift();
				else
					delete superContext[slotIdx];
			}

			return res;
		}
	}
});

/* 模拟 LuCI 的类层次：Abstract（无 renderWidget）→ Value（定义了 renderWidget） */
const Abstract = Class.extend({
	__name__: 'CBI.AbstractValue',
	parse() { return 'parsed'; }
});

const Value = Abstract.extend({
	__name__: 'CBI.Value',
	renderWidget() { return 'WIDGET-NODE'; }
});

/* A：实例属性方式（我原来的写法、也是 argon-config 的写法） */
const inst = new Value();
inst.renderWidget = function() {
	return 'A -> ' + String(this.super('renderWidget', []));
};
console.log('实例属性写法  :', inst.renderWidget());

/* B：子类方式（把 renderWidget 定义在类原型上） */
const MyValue = Value.extend({
	__name__: 'CBI.MyValue',
	renderWidget() {
		return 'B -> ' + String(this.super('renderWidget', []));
	}
});
const inst2 = new MyValue();
console.log('类继承写法    :', inst2.renderWidget());

/* C：实例属性但显式补上"当前类层"来验证查找起点 */
console.log('原型链检查    : Value.prototype 有 renderWidget =',
	Object.prototype.hasOwnProperty.call(Value.prototype, 'renderWidget'));
console.log('原型链检查    : Abstract.prototype 有 renderWidget =',
	Object.prototype.hasOwnProperty.call(Abstract.prototype, 'renderWidget'));
