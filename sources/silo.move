module dos_silo::silo;

use std::u64::min;
use sui::table_vec::{Self, TableVec};

//=== Structs ===

public struct SILO has drop {}

public enum SiloState has copy, drop, store {
    FILLING,
    READY,
}

public struct Silo<phantom ITEM: key + store> has key, store {
    id: UID,
    state: SiloState,
    // The number of items that can be stored in the silo.
    // If `capacity` is None, then capacity is uncapped.
    capacity: u64,
    // The items currently stored in the silo.
    items: TableVec<ITEM>,
}

//=== Errors ===

const ESiloFilling: u64 = 0;
const ESiloReady: u64 = 1;
const ECapacityTooLow: u64 = 2;

//=== Public Functions ===

public fun new<ITEM: key + store>(capacity: u64, ctx: &mut TxContext): Silo<ITEM> {
    let silo = Silo {
        id: object::new(ctx),
        state: SiloState::FILLING,
        capacity,
        items: table_vec::empty(ctx),
    };

    silo
}

public fun add_item<ITEM: key + store>(self: &mut Silo<ITEM>, item: ITEM) {
    match (self.state) {
        SiloState::FILLING => {
            // Add the item to the silo.
            self.items.push_back(item);
            // If the silo has a capacity, and the number of items in the silo
            // is equal to the capacity, set the silo state to FULL.
            if (self.items.length() == self.capacity) {
                self.state = SiloState::READY;
            }
        },
        SiloState::READY => abort ESiloReady,
    }
}

public fun remove_item<ITEM: key + store>(self: &mut Silo<ITEM>): ITEM {
    match (self.state) {
        SiloState::FILLING => abort ESiloFilling,
        SiloState::READY => { self.items.pop_back() },
    }
}

public fun remove_items<ITEM: key + store>(self: &mut Silo<ITEM>, mut quantity: u64): vector<ITEM> {
    match (self.state) {
        SiloState::FILLING => abort ESiloFilling,
        SiloState::READY => {
            vector::tabulate!(min(quantity, self.items.length()), |_| self.items.pop_back())
        },
    }
}

public fun set_capacity<ITEM: key + store>(self: &mut Silo<ITEM>, capacity: u64) {
    // Ensure the capacity is greater than the number of items currentlyin the silo.
    assert!(capacity >= self.items.length(), ECapacityTooLow);
    // Set the capacity.
    self.capacity = capacity;
    // If the capacity is now equal to the number of items in the silo, set the state to READY.
    if (self.capacity == self.items.length()) {
        self.state = SiloState::READY;
    }
}

//=== View Functions ===

public fun size<ITEM: key + store>(self: &Silo<ITEM>): u64 {
    self.items.length()
}

public fun capacity<ITEM: key + store>(self: &Silo<ITEM>): u64 {
    self.capacity
}

public fun is_filling<ITEM: key + store>(self: &Silo<ITEM>): bool {
    match (self.state) {
        SiloState::FILLING => true,
        SiloState::READY => false,
    }
}

public fun is_ready<ITEM: key + store>(self: &Silo<ITEM>): bool {
    match (self.state) {
        SiloState::FILLING => false,
        SiloState::READY => true,
    }
}
