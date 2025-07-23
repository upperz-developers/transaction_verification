// src/lib.cairo
// Definition of custom types for a sale and an item.
// Derive Drop, Serde, Copy, Store to be able to store and serialize these structs.
#[derive(Drop, Serde, Copy, starknet::Store)]
pub struct Item {
    pub id: u128,
    pub price_ht: u128,  // price excluding tax (u128 as requested)
}
#[derive(Drop, Serde, Copy, starknet::Store)]
pub struct SaleData {
    pub buyer: felt252,   // buyer identifier
    pub total_ht: u128,
    pub tva_amount: u128,
    pub total_ttc: u128,
}

// This struct is NOT stored persistently (it contains Array<Item>).
// It is used to return the data of a sale in get_sale (requires Serde).
#[derive(Drop, Serde)]
pub struct Sale {
    pub buyer: felt252,
    pub items: Array<Item>,       // sale items, stored in a dynamic array
    pub total_ht: u128,
    pub tva_amount: u128,
    pub total_ttc: u128,
}

// Interface for the Sales contract, defining the methods available.
// This allows other contracts to interact with the Sales contract without needing to know its internal implementation.
#[starknet::interface]
pub trait ISales<TContractState> {
    fn set_tva_rate(ref self: TContractState, new_rate: u128);
    fn record_sale(ref self: TContractState, buyer: felt252, items: Array<Item>);
    fn get_sale(self: @TContractState, sale_id: u128) -> Sale;
    fn get_sale_count(self: @TContractState) -> u128;
    fn get_tva_rate(self: @TContractState) -> u128;
}

#[starknet::contract]
pub mod SalesContract {
    use super::{Item, SaleData, Sale};
    use starknet::storage::{
        //
        StoragePointerReadAccess, StoragePointerWriteAccess,
        Vec, VecTrait, MutableVecTrait,
        Map, StorageMapReadAccess, StorageMapWriteAccess,
    };
    use core::array::Array;
    use core::array::ArrayTrait;
    
    #[storage]
    pub struct Storage {
        //
        sale_count: u128,
        // Current VAT rate (as an integer percentage, e.g., 20 for 20%)
        tva_rate: u128,
        // Sale data (excluding items) stored by sale ID
        sales: Map<u128, SaleData>,
        // for all sales, we store the offset and count of items in the persistent Vec
        // offset: position of the first item in the Vec, count: number of items in
        sale_items_offset: Map<u128, u64>,
        sale_items_count: Map<u128, u64>,
        // Persistent Vec to store all items across all sales
        items: Vec<Item>,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        // initialize the contract state
        self.sale_count.write(0_u128);
        self.tva_rate.write(20_u128); // Default VAT rate set to 20%
    }

    #[abi(embed_v0)]
    impl SalesContractImpl of super::ISales<ContractState> {
        // define the methods of the ISales interface
        fn set_tva_rate(ref self: ContractState, new_rate: u128) {
            self.tva_rate.write(new_rate);
        }
        // return the current VAT rate.
        fn get_tva_rate(self: @ContractState) -> u128 {
            self.tva_rate.read()
        }
        // return the current sale count (0-based).
        fn get_sale_count(self: @ContractState) -> u128 {
            self.sale_count.read()
        }

        fn record_sale(ref self: ContractState, buyer: felt252, items: Array<Item>) {
            // 1. calculate the total HT (excluding tax) for the sale
            let mut total_ht: u128 = 0;
            let span_items = items.span();
            for i in 0..span_items.len() {
                let it: Item = *span_items.at(i);  
                total_ht = total_ht + it.price_ht;
            }

            // 2. Calculate VAT and total including tax
            let rate = self.tva_rate.read();
            let tva_amount = total_ht * rate / 100_u128;
            let total_ttc = total_ht + tva_amount;

            // 3. Get the current sale ID (0-based)
            let sale_id = self.sale_count.read();

            // 4. Save the sale data (excluding items)
            self.sales.write(sale_id, SaleData {
                buyer: buyer,
                total_ht: total_ht,
                tva_amount: tva_amount,
                total_ttc: total_ttc,
            });

            // 5. Store the items in the persistent Vec
            let offset_u64: u64 = self.items.len().into();        // start position in the Vec
            let count_u64: u64 = items.len().into();             // number of items
            self.sale_items_offset.write(sale_id, offset_u64);
            self.sale_items_count.write(sale_id, count_u64);

            // Push each item into the Vec (compliant with Vec.push())
            let count: u32 = count_u64.try_into().unwrap();
            for i in 0..count {
                let it: Item = *items.at(i);
                self.items.push(it);
            }

            // 6. Finally, increment the sale counter
            self.sale_count.write(sale_id + 1);
        }

        // Retrieve a sale by ID, return a complete Sale struct (buyer, items, totals).
        fn get_sale(self: @ContractState, sale_id: u128) -> Sale {
            // Read the basic sale data
            let sale_data = self.sales.read(sale_id);

            // Retrieve offset and number of items
            let offset = self.sale_items_offset.read(sale_id);
            let count = self.sale_items_count.read(sale_id);

            // Build an Array<Item> in memory with the sale's items.
            let mut arr = array![];
            for i in 0..count {
                let it = self.items.at(offset + i).read();
                arr.append(it);
            }

            // Return the Sale struct
            Sale {
                buyer: sale_data.buyer,
                items: arr,
                total_ht: sale_data.total_ht,
                tva_amount: sale_data.tva_amount,
                total_ttc: sale_data.total_ttc,
            }
        }
    }
}
