package coff
import "core:mem"

SECT_TEXT::1;
SECT_DATA::2;
SECT_DEBUG_S::3;
SECT_DEBUG_T::4;
SECT_DIRECTIVE::5;

IMAGE_REL_AMD64_REL32::4;
IMAGE_REL_AMD64_SECTION::0xa;
IMAGE_REL_AMD64_SECREL::0xb;

IMAGE_FILE_MACHINE_AMD64::0x8664;

IMAGE_SCN_CNT_CODE::0x20;
IMAGE_SCN_ALIGN_16BYTES::0x00500000;
IMAGE_SCN_ALIGN_4BYTES::0x00300000;
IMAGE_SCN_MEM_EXECUTE::0x20000000;
IMAGE_SCN_MEM_READ::0x40000000;
IMAGE_SCN_MEM_WRITE::0x80000000;
IMAGE_SCN_MEM_DISCARDABLE::0x02000000;
IMAGE_SCN_ALIGN_1BYTES::0x00100000;
IMAGE_SCN_CNT_INITIALIZED_DATA :: 0x40;
IMAGE_SCN_LNK_INFO::0x00000200;
IMAGE_SCN_LNK_REMOVE::0x00000800;

IMAGE_SYM_DTYPE_FUNCTION:: 2;

IMAGE_SYM_CLASS_FUNCTION :: 101;
IMAGE_SYM_CLASS_STATIC :: 3;
IMAGE_SYM_CLASS_EXTERNAL :: 2;
IMAGE_SYM_CLASS_SECTION :: 104;
IMAGE_SYM_CLASS_UNDEFINED_STATIC::14;
MAGE_SYM_CLASS_EXTERNAL_DEF::5;
IMAGE_SYM_CLASS_LABEL::6;
IMAGE_SYM_CLASS_UNDEFINED_LABEL::7;
IMAGE_SYM_CLASS_FILE::103;

symbol_table_struct::struct #packed
{
	name : u64,
	value : u32,
	section_number : u16,
	type : u16,
	storage_class : u8,
	number_of_aux_symbols : u8,
}
relocation::struct #packed
{
	virtual_address : u32,
	symbol_table_index : u32,
	type : u16,
}
coff_header_struct::struct #packed
{
	machine : u16,
	number_of_sections : u16,
	time_date_stamp : u32,
	ptr_to_symbol_table : u32,
	number_of_symbols : u32,
	size_of_optional_header: u16,
	characteristics : u16,
}
section_table_struct::struct #packed
{
	name : u64,
	physical_address : u32,
	virtual_address : u32,
	size_of_raw_data : u32,
	ptr_to_raw_data : u32,
	ptr_to_relocations : u32,
	pointer_to_line_nums : u32,
	num_of_relocations : u16,
	num_of_line_nums : u16,
	characteristics: u32,
}

memcmp :: proc(l : ^u8, r : ^u8, len : int) -> bool
{
	i := 0;
	a := mem.slice_ptr(l, len);
	b := mem.slice_ptr(r, len);
	for i < len
	{
		if(a[i] ~ b[i] != 0)
		{
			return false;
		}
		i+=1;
	}
	return true;
}

search_symbol_v2::proc(info : ^coff_info, name : ^string) -> (i32)
{
	i := 0;

	symb :^symbol_table_struct= &info.symbol_table[0];
	name_c := transmute(cstring)(transmute(^^u32)(name))^;
	for ;i < cast(int)len(info.symbol_table); i+=1
	{
		if (symb.name & 0xffffff) == 0
		{
			name_uintptr := transmute(uintptr)(info.string_table) + cast(uintptr)(symb.name >> 32);
			name_on_str_table := transmute(cstring)(name_uintptr - 4);
			if memcmp(transmute(^u8)name_c, transmute(^u8)name_on_str_table, len(name_c))
			{
				return cast(i32)i;
			}
		}
		else
		{
			symb_name :cstring= transmute(cstring)(&symb.name);
			
			if name_c == symb_name
			{
				return cast(i32)i;
			}

		}
		symb = transmute(^symbol_table_struct)(cast(uintptr)(symb) + cast(uintptr)(size_of(symbol_table_struct)));
	}
	return -1;
}

coff_push_relocation::proc(info : ^coff_info, vaddr, symidx : u32, type : u16)
{
	l := len(info.sect_info);
	cur_sect_info := info.sect_info[l-1];
	if cur_sect_info.sect.num_of_relocations == 0
	{
		cur_sect_info.sect.ptr_to_relocations = info.raw_data_occuppied;
	}
	rel := transmute(^relocation)coff_push_reloc_data(info, size_of(relocation));
	rel.virtual_address = vaddr;
	rel.symbol_table_index = symidx;
	rel.type = type;

	cur_sect_info.sect.num_of_relocations += 1;
}
coff_push_raw_data::proc(info : ^coff_info, data : rawptr, sz : u32)
{
	dst := cast(uintptr)(info.raw_data) + cast(uintptr)(info.raw_data_occuppied); 
	mem.copy(cast(rawptr)dst, data, cast(int)sz);
	

	l := len(info.sect_info);
	cur_sect_info := info.sect_info[l-1];
	cur_sect_info.sect.size_of_raw_data += sz;
	cur_sect_info.sect.ptr_to_raw_data = info.raw_data_occuppied;
	info.raw_data_occuppied += sz;
}
coff_push_reloc_data::proc(info : ^coff_info, sz : u32) -> rawptr
{
	dst := cast(uintptr)(info.raw_data) + cast(uintptr)(info.raw_data_occuppied); 
	info.raw_data_occuppied += sz;

	l := len(info.sect_info);
	cur_sect_info := info.sect_info[l-1];

	return cast(rawptr)dst;
}


coff_begin_section::proc(info : ^coff_info, type : u32)
{
	new_sect := transmute(^sect_info)coff_push_data_scratch(info, size_of(sect_info));
	sect_hdr := transmute(^section_table_struct)coff_push_data(info, size_of(section_table_struct));
	
	new_sect.sect = sect_hdr;
	sect_name :cstring;

	switch type
	{
		case SECT_TEXT:
		{
			sect_name = ".text$mn";
			sect_hdr.name = (cast(^^u64)(&sect_name))^^;
			sect_hdr.characteristics = IMAGE_SCN_CNT_CODE|IMAGE_SCN_ALIGN_16BYTES|IMAGE_SCN_MEM_EXECUTE|IMAGE_SCN_MEM_READ;
		}
		case SECT_DATA:
		{
			sect_name = ".data";
			sect_hdr.name = (cast(^^u64)(&sect_name))^^;
			sect_hdr.characteristics = IMAGE_SCN_CNT_INITIALIZED_DATA|IMAGE_SCN_ALIGN_4BYTES|IMAGE_SCN_MEM_READ;
		}
		case SECT_DEBUG_S:
		{
			sect_name = ".debug$S";
			sect_hdr.name = (cast(^^u64)(&sect_name))^^;
			sect_hdr.characteristics  = IMAGE_SCN_MEM_READ|IMAGE_SCN_ALIGN_1BYTES|IMAGE_SCN_CNT_INITIALIZED_DATA;
		}
		case SECT_DEBUG_T:
		{
			sect_name = ".debug$T";
			sect_hdr.name = (cast(^^u64)(&sect_name))^^;
			sect_hdr.characteristics  = IMAGE_SCN_MEM_READ|IMAGE_SCN_ALIGN_1BYTES|IMAGE_SCN_CNT_INITIALIZED_DATA;
		}
		case SECT_DIRECTIVE:
		{
			sect_name = ".drtectve";
			sect_hdr.name = (cast(^^u64)(&sect_name))^^;
			sect_hdr.characteristics = IMAGE_SCN_LNK_INFO|IMAGE_SCN_ALIGN_1BYTES|IMAGE_SCN_LNK_REMOVE;
		}
	}

	info.cur_sect += 1;
	append(&info.sect_info, new_sect);
}
coff_end_section::proc(info : ^coff_info)
{
	l := info.cur_sect;
	cur_sect_info := &info.sect_info[l-1];
	info.cur_sect -= 1;
	info.coff_hdr.number_of_sections += 1;
}



sect_info::struct
{
	sect : ^section_table_struct,
	reloc : [dynamic]relocation,
}
coff_info::struct
{
	data : rawptr,
	occuppied : u32,

	raw_data : rawptr,
	raw_data_occuppied : u32,

	scratch_buffer : rawptr,
	scratch_occuppied : u32,

	coff_hdr : ^coff_header_struct,

	symbol_table : [dynamic]symbol_table_struct,
	string_table : rawptr,
	string_table_sz : u32,

	cur_sect : u32,

	sect_info : [dynamic]^sect_info,
}

coff_push_data_scratch::proc(info : ^coff_info, data_size : u32) -> rawptr 
{
	data := cast(uintptr)(info.scratch_buffer) + cast(uintptr)(info.scratch_occuppied);
	info.scratch_occuppied += data_size;
	return cast(rawptr)data;
}
coff_push_data::proc(info : ^coff_info, data_size : u32) -> rawptr 
{
	data := cast(uintptr)(info.data) + cast(uintptr)(info.occuppied);
	info.occuppied += data_size;
	return cast(rawptr)data;
}


coff_begin_coff::proc(info : ^coff_info)
{
	coff_hdr := transmute(^coff_header_struct)coff_push_data(info, size_of(coff_header_struct));
	info.coff_hdr = coff_hdr;
	coff_hdr.machine = 0x8664;
}
coff_end_coff::proc(info : ^coff_info) -> (rawptr, u32)
{
	stbl_byte_sz :u32= cast(u32)(size_of(symbol_table_struct) * len(info.symbol_table));
	sz := info.occuppied + info.raw_data_occuppied + stbl_byte_sz  + info.string_table_sz + 32;
	final_buffer := mem.alloc(cast(int)sz);
	i := 0;
	for ;i < len(info.sect_info);i +=1
	{
		cur_sect := info.sect_info[i];
		cur_sect.sect.ptr_to_raw_data += info.occuppied;
		if cur_sect.sect.num_of_relocations != 0
		{
			cur_sect.sect.ptr_to_relocations += info.occuppied;
		}
	}
	// sections data
	mem.copy(final_buffer, cast(rawptr)info.data, cast(int)info.occuppied);
	
	// raw data
	dst := cast(uintptr)(final_buffer) + cast(uintptr)(info.occuppied);
	mem.copy(cast(rawptr)dst, cast(rawptr)info.raw_data, cast(int)info.raw_data_occuppied);
	
	// symbol table
	dst = cast(uintptr)(dst) + cast(uintptr)(info.raw_data_occuppied);
	info.coff_hdr = transmute(^coff_header_struct)final_buffer;
	info.coff_hdr.ptr_to_symbol_table = cast(u32)(cast(uintptr)(dst) - cast(uintptr)(final_buffer));
	mem.copy(cast(rawptr)dst, cast(rawptr)&info.symbol_table[0], cast(int)stbl_byte_sz);
	
	//string table
	dst = cast(uintptr)(dst) + cast(uintptr)(stbl_byte_sz);
	(transmute(^u32)dst)^ = stbl_byte_sz;
	dst += cast(uintptr)(4);

	mem.copy(cast(rawptr)dst, cast(rawptr)info.string_table, cast(int)info.string_table_sz);
	return final_buffer, sz;
}

coff_push_symbol::proc(info : ^coff_info, name : string, value :u32, type, section_number : u16, number_of_aux_symbols, storage_class : u8)
{

	make_symbol_type::inline proc(t1, t2 : u8) -> u16
	{
		return cast(u16)(t1 | ( t2 << 4));
	}

	symbol_final :symbol_table_struct;

	n := name;
	str_len := len(name);
	name_c := transmute(cstring)(transmute(^^u32)(&n))^;

	if str_len  < 7
	{
		mem.copy(transmute(rawptr)&symbol_final.name, cast(rawptr)name_c, str_len);
	}
	else
	{
		
		offset_to_string_tbl := info.string_table_sz;
		symbol_final.name |= cast(u64)offset_to_string_tbl << cast(u64)32;

		string_table_end :uintptr= transmute(uintptr)(info.string_table) + cast(uintptr)(offset_to_string_tbl - 4);
		mem.copy(transmute(rawptr)string_table_end, cast(rawptr)name_c, str_len);
		info.string_table_sz += cast(u32)(str_len + 1);
	}
		
	symbol_final.value = value;
	symbol_final.type = make_symbol_type(0, cast(u8)type);
	symbol_final.storage_class = storage_class;
	symbol_final.number_of_aux_symbols = number_of_aux_symbols;

	info.coff_hdr.number_of_symbols += 1;
	append(&info.symbol_table, symbol_final);
}
