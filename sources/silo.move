module dos_silo::silo;

use std::type_name::{Self, TypeName};
use std::u64::min;
use sui::event::emit;
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

public struct SiloAdminCap has key, store {
    id: UID,
    silo_id: ID,
}

public struct SiloCreatedEvent has copy, drop {
    silo_id: ID,
    silo_admin_cap_id: ID,
}

public struct SiloDestroyedEvent has copy, drop {
    silo_id: ID,
}

public struct SiloItemAddedEvent has copy, drop {
    silo_id: ID,
    item_id: ID,
}

public struct SiloItemRemovedEvent has copy, drop {
    silo_id: ID,
    item_id: ID,
}

public struct SiloCapacitySetEvent has copy, drop {
    silo_id: ID,
    capacity: u64,
}

//=== Errors ===

const ESiloFilling: u64 = 0;
const ESiloReady: u64 = 1;
const ESiloNotEmpty: u64 = 2;
const ECapacityTooLow: u64 = 3;
const EInvalidSiloAdminCap: u64 = 4;

//=== Public Functions ===

public fun new<ITEM: key + store>(capacity: u64, ctx: &mut TxContext): (Silo<ITEM>, SiloAdminCap) {
    let silo = Silo {
        id: object::new(ctx),
        state: SiloState::FILLING,
        capacity,
        items: table_vec::empty(ctx),
    };

    let silo_admin_cap = SiloAdminCap {
        id: object::new(ctx),
        silo_id: silo.id.to_inner(),
    };

    emit(SiloCreatedEvent {
        silo_id: silo.id.to_inner(),
        silo_admin_cap_id: object::id(&silo_admin_cap),
    });

    (silo, silo_admin_cap)
}

// Destroy an empty silo.
public fun destroy_silo<ITEM: key + store>(self: Silo<ITEM>, cap: SiloAdminCap) {
    assert!(cap.silo_id == self.id.to_inner(), EInvalidSiloAdminCap);
    assert!(self.items.is_empty(), ESiloNotEmpty);

    let Silo { id, items, .. } = self;
    id.delete();
    items.destroy_empty();

    let SiloAdminCap { id, .. } = cap;
    id.delete()
}

public fun add_item<ITEM: key + store>(self: &mut Silo<ITEM>, cap: &SiloAdminCap, item: ITEM) {
    assert!(cap.silo_id == self.id.to_inner(), EInvalidSiloAdminCap);

    match (self.state) {
        SiloState::FILLING => {
            emit(SiloItemAddedEvent {
                silo_id: self.id.to_inner(),
                item_id: object::id(&item),
            });
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

public fun remove_item<ITEM: key + store>(self: &mut Silo<ITEM>, cap: &SiloAdminCap): ITEM {
    assert!(cap.silo_id == self.id.to_inner(), EInvalidSiloAdminCap);

    match (self.state) {
        SiloState::FILLING => abort ESiloFilling,
        SiloState::READY => {
            let item = self.items.pop_back();

            emit(SiloItemRemovedEvent {
                silo_id: self.id.to_inner(),
                item_id: object::id(&item),
            });

            item
        },
    }
}

public fun remove_items<ITEM: key + store>(
    self: &mut Silo<ITEM>,
    cap: &SiloAdminCap,
    quantity: u64,
): vector<ITEM> {
    assert!(cap.silo_id == self.id.to_inner(), EInvalidSiloAdminCap);

    match (self.state) {
        SiloState::FILLING => abort ESiloFilling,
        SiloState::READY => {
            vector::tabulate!(min(quantity, self.items.length()), |_| self.items.pop_back())
        },
    }
}

public fun set_capacity<ITEM: key + store>(
    self: &mut Silo<ITEM>,
    cap: &SiloAdminCap,
    capacity: u64,
) {
    assert!(cap.silo_id == self.id.to_inner(), EInvalidSiloAdminCap);

    // Ensure the capacity is greater than the number of items currentlyin the silo.
    assert!(capacity >= self.items.length(), ECapacityTooLow);

    // Set the capacity.
    self.capacity = capacity;

    // If the capacity is now equal to the number of items in the silo, set the state to READY.
    if (self.capacity == self.items.length()) {
        self.state = SiloState::READY;
    };

    emit(SiloCapacitySetEvent {
        silo_id: self.id.to_inner(),
        capacity,
    });
}

//=== View Functions ===

public fun size<ITEM: key + store>(self: &Silo<ITEM>): u64 {
    self.items.length()
}

public fun capacity<ITEM: key + store>(self: &Silo<ITEM>): u64 {
    self.capacity
}

public fun item_type<ITEM: key + store>(): TypeName {
    type_name::get<ITEM>()
}

public fun is_filling_state<ITEM: key + store>(self: &Silo<ITEM>): bool {
    match (self.state) {
        SiloState::FILLING => true,
        SiloState::READY => false,
    }
}

public fun is_ready_state<ITEM: key + store>(self: &Silo<ITEM>): bool {
    match (self.state) {
        SiloState::FILLING => false,
        SiloState::READY => true,
    }
}
