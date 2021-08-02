/*
 * This source file is part of RmlUi, the HTML/CSS Interface Middleware
 *
 * For the latest information, see http://github.com/mikke89/RmlUi
 *
 * Copyright (c) 2008-2010 CodePoint Ltd, Shift Technology Ltd
 * Copyright (c) 2019 The RmlUi Team, and contributors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */

#ifndef RMLUI_CORE_DATAMODELHANDLE_H
#define RMLUI_CORE_DATAMODELHANDLE_H

#include "Header.h"
#include "Types.h"
#include "Traits.h"
#include "DataTypes.h"
#include "DataVariable.h"

namespace Rml {

class DataModel;


class RMLUICORE_API DataModelHandle {
public:
	DataModelHandle(DataModel* model = nullptr);

	bool IsVariableDirty(const std::string& variable_name);
	void DirtyVariable(const std::string& variable_name);

	explicit operator bool() { return model; }

private:
	DataModel* model;
};


class RMLUICORE_API DataModelConstructor {
public:
	template<typename T>
	using DataEventMemberFunc = void(T::*)(DataModelHandle, Event&, const VariantList&);

	DataModelConstructor();
	DataModelConstructor(DataModel* model);

	// Return a handle to the data model being constructed, which can later be used to synchronize variables and update the model.
	DataModelHandle GetModelHandle() const;

	// Bind a get/set function pair.
	bool BindFunc(const std::string& name, DataGetFunc get_func, DataSetFunc set_func = {});

	// Bind an event callback.
	bool BindEventCallback(const std::string& name, DataEventFunc event_func);

	// Convenience wrapper around BindEventCallback for member functions.
	template<typename T>
	bool BindEventCallback(const std::string& name, DataEventMemberFunc<T> member_func, T* object_pointer) {
		return BindEventCallback(name, [member_func, object_pointer](DataModelHandle handle, Event& event, const VariantList& arguments) {
			(object_pointer->*member_func)(handle, event, arguments);
		});
	}

	// Bind a user-declared DataVariable.
	// For advanced use cases, for example for binding variables to a custom 'VariableDefinition'.
	bool BindCustomDataVariable(const std::string& name, DataVariable data_variable) {
		return BindVariable(name, data_variable);
	}

	explicit operator bool() { return model; }

private:
	bool BindVariable(const std::string& name, DataVariable data_variable);

	DataModel* model;
};

} // namespace Rml

#endif
