#include "llvm/Constants.h"
#include "llvm/DerivedTypes.h"

#include "aggregate.h"
#include "declaration.h"
#include "mtype.h"

#include "gen/irstate.h"
#include "gen/logger.h"
#include "gen/tollvm.h"
#include "gen/llvmhelpers.h"
#include "gen/utils.h"
#include "gen/arrays.h"

#include "ir/irstruct.h"
#include "ir/irtypeclass.h"

//////////////////////////////////////////////////////////////////////////////

extern LLConstant* get_default_initializer(VarDeclaration* vd, Initializer* init);
extern size_t add_zeros(std::vector<llvm::Constant*>& constants, size_t diff);

extern LLConstant* DtoDefineClassInfo(ClassDeclaration* cd);

//////////////////////////////////////////////////////////////////////////////

LLGlobalVariable * IrStruct::getVtblSymbol()
{
    if (vtbl)
        return vtbl;

    // create the initZ symbol
    std::string initname("_D");
    initname.append(aggrdecl->mangle());
    initname.append("6__vtblZ");

    llvm::GlobalValue::LinkageTypes _linkage = DtoExternalLinkage(aggrdecl);

    const LLType* vtblTy = type->irtype->isClass()->getVtbl();

    vtbl = new llvm::GlobalVariable(
        vtblTy, true, _linkage, NULL, initname, gIR->module);

    return vtbl;
}

//////////////////////////////////////////////////////////////////////////////

LLGlobalVariable * IrStruct::getClassInfoSymbol()
{
    if (classInfo)
        return classInfo;

    // create the initZ symbol
    std::string initname("_D");
    initname.append(aggrdecl->mangle());
    if (aggrdecl->isInterfaceDeclaration())
        initname.append("11__InterfaceZ");
    else
        initname.append("7__ClassZ");

    llvm::GlobalValue::LinkageTypes _linkage = DtoExternalLinkage(aggrdecl);

    ClassDeclaration* cinfo = ClassDeclaration::classinfo;
    DtoType(cinfo->type);
    IrTypeClass* tc = cinfo->type->irtype->isClass();
    assert(tc && "invalid ClassInfo type");

    classInfo = new llvm::GlobalVariable(
        tc->getPA().get(), true, _linkage, NULL, initname, gIR->module);

    return classInfo;
}

//////////////////////////////////////////////////////////////////////////////

LLGlobalVariable * IrStruct::getInterfaceArraySymbol()
{
    if (classInterfacesArray)
        return classInterfacesArray;

    ClassDeclaration* cd = aggrdecl->isClassDeclaration();

    assert(cd->vtblInterfaces && cd->vtblInterfaces->dim > 0 &&
        "should not create interface info array for class with no explicit "
        "interface implementations");

    VarDeclarationIter idx(ClassDeclaration::classinfo->fields, 3);
    const llvm::Type* InterfaceTy = DtoType(idx->type->next);

    // create Interface[N]
    const llvm::ArrayType* array_type = llvm::ArrayType::get(
        InterfaceTy,
        cd->vtblInterfaces->dim);

    // put it in a global
    std::string name("_D");
    name.append(cd->mangle());
    name.append("16__interfaceInfosZ");
    classInterfacesArray = new llvm::GlobalVariable(array_type, true, DtoLinkage(cd), NULL, name, classInfo);

    return classInterfacesArray;
}

//////////////////////////////////////////////////////////////////////////////

LLConstant * IrStruct::getVtblInit()
{
    if (constVtbl)
        return constVtbl;

    IF_LOG Logger::println("Building vtbl initializer");
    LOG_SCOPE;

    ClassDeclaration* cd = aggrdecl->isClassDeclaration();
    assert(cd && "not class");

    std::vector<llvm::Constant*> constants;
    constants.reserve(cd->vtbl.dim);

    // start with the classinfo
    llvm::Constant* c = getClassInfoSymbol();
    c = DtoBitCast(c, DtoType(ClassDeclaration::classinfo->type));
    constants.push_back(c);

    // add virtual function pointers
    size_t n = cd->vtbl.dim;
    for (size_t i = 1; i < n; i++)
    {
        Dsymbol* dsym = (Dsymbol*)cd->vtbl.data[i];
        assert(dsym && "null vtbl member");

        FuncDeclaration* fd = dsym->isFuncDeclaration();
        assert(fd && "vtbl entry not a function");

        if (fd->isAbstract() && !fd->fbody)
        {
            c = getNullValue(DtoType(fd->type->pointerTo()));
        }
        else
        {
            fd->codegen(Type::sir);
            assert(fd->ir.irFunc && "invalid vtbl function");
            c = fd->ir.irFunc->func;
        }
        constants.push_back(c);
    }

    // build the constant struct
    constVtbl = llvm::ConstantStruct::get(constants, false);

    // sanity check
#if 0
    IF_LOG Logger::cout() << "constVtbl type: " << *constVtbl->getType() << std::endl;
    IF_LOG Logger::cout() << "vtbl type: " << *type->irtype->isClass()->getVtbl() << std::endl;
#endif

    assert(constVtbl->getType() == type->irtype->isClass()->getVtbl() &&
        "vtbl initializer type mismatch");

    return constVtbl;
}

//////////////////////////////////////////////////////////////////////////////

LLConstant * IrStruct::getClassInfoInit()
{
    if (constClassInfo)
        return constClassInfo;
    constClassInfo = DtoDefineClassInfo(aggrdecl->isClassDeclaration());
    return constClassInfo;
}

//////////////////////////////////////////////////////////////////////////////

void IrStruct::addBaseClassInits(
    std::vector<llvm::Constant*>& constants,
    ClassDeclaration* base,
    size_t& offset,
    size_t& field_index)
{
    if (base->baseClass)
    {
        addBaseClassInits(constants, base->baseClass, offset, field_index);
    }

    ArrayIter<VarDeclaration> it(base->fields);
    for (; !it.done(); it.next())
    {
        VarDeclaration* vd = it.get();

        // skip if offset moved backwards
        if (vd->offset < offset)
        {
            IF_LOG Logger::println("Skipping field %s %s (+%u) for default", vd->type->toChars(), vd->toChars(), vd->offset);
            continue;
        }

        IF_LOG Logger::println("Adding default field %s %s (+%u)", vd->type->toChars(), vd->toChars(), vd->offset);
        LOG_SCOPE;

        // get next aligned offset for this type
        size_t alignsize = vd->type->alignsize();
        size_t alignedoffset = (offset + alignsize - 1) & ~(alignsize - 1);

        // insert explicit padding?
        if (alignedoffset < vd->offset)
        {
            add_zeros(constants, vd->offset - alignedoffset);
        }

        // add default type
        constants.push_back(get_default_initializer(vd, vd->init));

        // advance offset to right past this field
        offset = vd->offset + vd->type->size();
    }

    // has interface vtbls?
    if (base->vtblInterfaces)
    {
        // false when it's not okay to use functions from super classes
        bool newinsts = (base == aggrdecl->isClassDeclaration());

        ArrayIter<BaseClass> it2(*base->vtblInterfaces);
        for (; !it2.done(); it2.next())
        {
            BaseClass* b = it2.get();
            constants.push_back(getInterfaceVtbl(b, newinsts));
            offset += PTRSIZE;
        }
    }

    // tail padding?
    if (offset < base->structsize)
    {
        add_zeros(constants, base->structsize - offset);
        offset = base->structsize;
    }
}

//////////////////////////////////////////////////////////////////////////////

LLConstant * IrStruct::createClassDefaultInitializer()
{
    ClassDeclaration* cd = aggrdecl->isClassDeclaration();
    assert(cd && "invalid class aggregate");

    IF_LOG Logger::println("Building class default initializer %s @ %s", cd->toPrettyChars(), cd->locToChars());
    LOG_SCOPE;
    IF_LOG Logger::println("Instance size: %u", cd->structsize);

    // find the fields that contribute to the default initializer.
    // these will define the default type.

    std::vector<llvm::Constant*> constants;
    constants.reserve(32);

    // add vtbl
    constants.push_back(getVtblSymbol());
    // add monitor
    constants.push_back(getNullValue(DtoType(Type::tvoid->pointerTo())));

    // we start right after the vtbl and monitor
    size_t offset = PTRSIZE * 2;
    size_t field_index = 2;

    // add data members recursively
    addBaseClassInits(constants, cd, offset, field_index);

    // build the constant
    llvm::Constant* definit = llvm::ConstantStruct::get(constants, false);

    // sanity check
    assert(definit->getType() == type->irtype->getPA().get() && "class initializer type mismatch");

    return definit;
}

//////////////////////////////////////////////////////////////////////////////

llvm::GlobalVariable * IrStruct::getInterfaceVtbl(BaseClass * b, bool new_instance)
{
    ClassDeclaration* cd = aggrdecl->isClassDeclaration();
    assert(cd && "not a class aggregate");

    ClassGlobalMap::iterator it = interfaceVtblMap.find(cd);
    if (it != interfaceVtblMap.end())
        return it->second;

    IF_LOG Logger::println("Building vtbl for implementation of interface %s in class %s",
        b->base->toPrettyChars(), aggrdecl->toPrettyChars());
    LOG_SCOPE;

    Array vtbl_array;
    b->fillVtbl(cd, &vtbl_array, new_instance);

    std::vector<llvm::Constant*> constants;
    constants.reserve(vtbl_array.dim);

    // start with the interface info
    llvm::Constant* c = getNullValue(DtoType(Type::tvoid->pointerTo()));
    constants.push_back(c);

    // add virtual function pointers
    size_t n = vtbl_array.dim;
    for (size_t i = 1; i < n; i++)
    {
        Dsymbol* dsym = (Dsymbol*)vtbl_array.data[i];
        assert(dsym && "null vtbl member");

        FuncDeclaration* fd = dsym->isFuncDeclaration();
        assert(fd && "vtbl entry not a function");

        assert(!(fd->isAbstract() && !fd->fbody) &&
            "null symbol in interface implementation vtable");

        fd->codegen(Type::sir);
        assert(fd->ir.irFunc && "invalid vtbl function");

        constants.push_back(fd->ir.irFunc->func);
    }

    // build the vtbl constant
    llvm::Constant* vtbl_constant = llvm::ConstantStruct::get(constants, false);

    // create the global variable to hold it
    llvm::GlobalValue::LinkageTypes _linkage = DtoExternalLinkage(aggrdecl);

    std::string mangle("_D");
    mangle.append(cd->mangle());
    mangle.append("11__interface");
    mangle.append(b->base->mangle());
    mangle.append("6__vtblZ");

    llvm::GlobalVariable* GV = new llvm::GlobalVariable(
        vtbl_constant->getType(),
        true,
        _linkage,
        vtbl_constant,
        mangle,
        gIR->module
    );

    interfaceVtblMap.insert(std::make_pair(b->base, GV));

    return GV;
}

//////////////////////////////////////////////////////////////////////////////

LLConstant * IrStruct::getClassInfoInterfaces()
{
    IF_LOG Logger::println("Building ClassInfo.interfaces");
    LOG_SCOPE;

    ClassDeclaration* cd = aggrdecl->isClassDeclaration();
    assert(cd);

    if (!cd->vtblInterfaces || cd->vtblInterfaces->dim == 0)
    {
        VarDeclarationIter idx(ClassDeclaration::classinfo->fields, 3);
        return getNullValue(DtoType(idx->type));
    }

// Build array of:
//
//     struct Interface
//     {
//         ClassInfo   classinfo;
//         void*[]     vtbl;
//         ptrdiff_t   offset;
//     }

    LLSmallVector<LLConstant*, 6> constants;
    constants.reserve(cd->vtblInterfaces->dim);

    const LLType* classinfo_type = DtoType(ClassDeclaration::classinfo->type);
    const LLType* voidptrptr_type = DtoType(
        Type::tvoid->pointerTo()->pointerTo());

    const LLType* our_type = type->irtype->isClass()->getPA().get();

    ArrayIter<BaseClass> it(*cd->vtblInterfaces);
    while (it.more())
    {
        IF_LOG Logger::println("Adding interface %s", it->base->toPrettyChars());

        IrStruct* irinter = it->base->ir.irStruct;
        assert(irinter && "interface has null IrStruct");
        IrTypeClass* itc = irinter->type->irtype->isClass();
        assert(itc && "null interface IrTypeClass");

        // classinfo
        LLConstant* ci = irinter->getClassInfoSymbol();
        ci = DtoBitCast(ci, classinfo_type);

        // vtbl
        ClassGlobalMap::iterator itv = interfaceVtblMap.find(it->base);
        assert(itv != interfaceVtblMap.end() && "interface vtbl not found");
        LLConstant* vtb = itv->second;
        vtb = DtoBitCast(vtb, voidptrptr_type);
        vtb = DtoConstSlice(DtoConstSize_t(itc->getVtblSize()), vtb);

        // offset
        LLConstant* off = DtoConstSize_t(it->offset);

        // create Interface struct
        LLConstant* inits[3] = { ci, vtb, off };
        LLConstant* entry = llvm::ConstantStruct::get(inits, 3);
        constants.push_back(entry);

        // next
        it.next();
    }

    // create Interface[N]
    const llvm::ArrayType* array_type = llvm::ArrayType::get(
        constants[0]->getType(),
        cd->vtblInterfaces->dim);

    LLConstant* arr = llvm::ConstantArray::get(
        array_type,
        &constants[0],
        constants.size());

    // apply the initializer
    classInterfacesArray->setInitializer(arr);

    LLConstant* idxs[2] = {
        DtoConstSize_t(0),
        DtoConstSize_t(0)
    };

    // return as a slice
    return DtoConstSlice(
        DtoConstSize_t(cd->vtblInterfaces->dim),
        llvm::ConstantExpr::getGetElementPtr(classInterfacesArray, idxs, 2));
}

//////////////////////////////////////////////////////////////////////////////
