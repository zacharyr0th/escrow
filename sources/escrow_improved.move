
/**
 * This module implements an escrow agreement mechanism between two parties.
 * The primary purpose is to allow two parties to lock assets in an escrow 
 * until specific conditions are met.
 * 
 * Escrow Flow:
 * 1. Parties initialize their accounts for the escrow mechanism.
 * 2. Initiator creates an escrow agreement specifying the responder, assets, and conditions.
 * 3. Responder can review and sign the agreement, locking their assets.
 * 4. Upon meeting conditions, assets are released to the respective parties.
 * 5. Agreements can be altered or cancelled under specific conditions for flexibility.
**/
module escrow_address::escrow {

    // This module implements an escrow agreement between two parties.
    
    use aptos_framework::account;
    use aptos_framework::event;
    use std::signer;
    use std::vector;
    use std::string::String;
    use 0x1::Signer;
    use 0x1::Balance;
    use std::vector;
    use std::table::{Self, Table};

    #[test_only]
    use std::string;

    // Error codes
    const E_NOT_INITIALIZED: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    const E_AGREEMENT_EXPIRED: u64 = 3; 
    const E_AGREEMENT_ALREADY_COMPLETED: u64 = 4;
    const E_AGREEMENT_NOT_EXPIRED: u64 = 5;
    const E_AGREEMENT_ID_ALREADY_EXISTS: u64 = 6;
    const E_INVALID_INITIATOR: u64 = 7;
    const E_RESPONDER_ALREADY_SIGNED: u64 = 8;
    const E_INVALID_SENDER: u64 = 9;
    const E_INSUFFICIENT_SENDER_BALANCE: u64 = 10;

    // Core data structures

    /// Represents a lock of coins until some specified unlock time. Afterward, the recipient can claim the coins.
    struct Lock<phantom CoinType> has store {
        coins: Coin<CoinType>,
        unlock_time_secs: u64,
    }

    // Resource for storing agreements
    struct AgreementStore<phantom CoinType> has store { 
        agreements: Table<address, Agreement<CoinType>>,
        escrow_account: address,
    }

    // Main structs - Agreement and AgreementCounter
    struct Agreement<phantom CoinType> has key { 
        initiator: address,         
        responder: option::Option<address>,  
        initiator_lock: Lock<CoinType>,
        responder_lock: Lock<CoinType>,
        expiration: u64,
        is_completed: bool,
        is_refundable: bool,

        agreement_created_event: event::EventHandle<AgreementCreatedEvent>,
        agreement_updated_event: event::EventHandle<AgreementUpdatedEvent>,
        agreement_completed_event: event::EventHandle<AgreementCompletedEvent>,
        agreement_cancelled_event: event::EventHandle<AgreementCancelledEvent>,
    }

    struct AgreementCounter {
        count: u64,
    }

   // Event structs
    struct AgreementCreatedEvent has drop, store { // Agreement created event
        agreement_id: u64,
        initiator: address,
        deposit: u64,
        expiration: u64,
    }
    struct AgreementUpdatedEvent has drop, store { // Agreement updated event
        agreement_id: u64,
        responder: address,
        deposit: u64,
    }
    struct AgreementCompletedEvent has drop, store { // Agreement completed event
        agreement_id: u64,
        responder: address,
        deposit: u64,
    }
    struct AgreementCancelledEvent has drop, store { // Agreement cancelled event
        agreement_id: u64,
        initiator: address,
        deposit: u64,
    }


    // public functions 
    public fun initialize_agreement_store() {
        let store = AgreementStore { agreements: vector::new() };
        move_to(0x1, store);
    }

    public fun initialize_agreement_counter(account: &signer) {
        move_to(account, AgreementCounter { count: 0 });
    }

    public fun get_agreement_store(): &mut AgreementStore {
        let store: &mut AgreementStore = &mut move_from(0x1);
        return store;
    }

    public fun get_escrow_account() {
        let store: &mut AgreementStore = &mut move_from(0x1);
        let escrow_account = store.escrow_account;
        return escrow_account;
    }

    public fun generate_unique_agreement_id(account: &signer) -> u64 {
        let addr = signer::address_of(account);
        let counter = borrow_global_mut<AgreementCounter>(addr);
        counter.count = counter.count + 1;
        counter.count
    }

    public fun get_current_timestamp() -> u64 {
        let sender = Signer::get_txn_sender();
        let current_block = Signer::get_block_metadata();
        let current_timestamp = current_block.timestamp;
        return current_timestamp;
    }

    public fun has_balance(account_addr: address, amount: u64) -> bool {
        let balance: &Balance.T = &move_from(account_addr);
        let account_balance: u64 = *balance;
        return account_balance >= amount;
    }

    public fun transfer_funds(from: address, to: address, amount: u64) {
        let sender = Signer::get_txn_sender();
        assert(from == sender, 77); // Ensure the sender is the same as the 'from' account

        let from_balance: &mut Balance.T = &mut move_from(from);
        let to_balance: &mut Balance.T = &mut move_from(to);

        assert(*from_balance >= amount, 78); // Ensure the 'from' account has enough balance

        *from_balance -= amount;
        *to_balance += amount;

        move_to_sender(from_balance);
        move_to_sender(to_balance);
    }

    public fun unlock_funds(account_addr: address, amount: u64) {
        let sender = Signer::get_txn_sender();
        assert(account_addr != sender, 77); // Ensure the account is not the sender's account

        let account_balance: &mut Balance.T = &mut move_from(account_addr);
        let sender_balance: &mut Balance.T = &mut move_from(sender);

        assert(*account_balance >= amount, 78); // Ensure the account has enough balance

        *account_balance -= amount;
        *sender_balance += amount;

        move_to_sender(account_balance);
        move_to_sender(sender_balance);
    }


    public fun get_agreement(agreement_id: u64) -> &mut Agreement {
        let store: &mut AgreementStore = &mut move_from(0x1);
        let agreement: &mut Agreement = &mut store.agreements[agreement_id as usize];
        return agreement;
    }

    public fun update_agreement(agreement_id: u64, agreement: &mut Agreement) {
        let store: &mut AgreementStore = &mut move_from(0x1);
        let existing_agreement: &mut Agreement = &mut store.agreements[agreement_id as usize];
        *existing_agreement = *agreement;
    }

    public fun expire_agreement(agreement_id: u64) {
        let agreement = get_agreement(agreement_id);
        let current_time = get_current_timestamp();
        assert!(current_time > agreement.expiration, E_AGREEMENT_NOT_EXPIRED);
        assert!(!agreement.is_completed, E_AGREEMENT_ALREADY_COMPLETED);

        if agreement.is_refundable {
            unlock_funds(agreement.initiator, agreement.initiator_deposit);
        } else {
            // Could handle non-refundable agreement expiration logic here
        }

        emit AgreementExpired(agreement_id);
    }

    public fun lock_funds(account: &signer, agreement_id: u64, amount: u64) {
        let initiator_addr = signer::address_of(account);
        let agreement = get_agreement(agreement_id); // Pull agreement
        assert!(initiator_addr == agreement.initiator, E_INVALID_INITIATOR); // Make sure caller is the initiator
        assert!(agreement.responder.is_none(), E_RESPONDER_ALREADY_SIGNED); // Make sure responder hasn't signed agreement yet

        let escrow_account = get_escrow_account(); // Get the address of the escrow account
        transfer_funds(initiator_addr, escrow_account, amount); // Transfer funds from the initiator to the escrow account

        // Update the agreement to reflect the locked funds
        agreement.initiator_deposit = amount;
        update_agreement(agreement_id, agreement);
    }

    // User functions
    public fun create_escrow(account: &signer, deposit: u64, expiration: u64, responder: address) {
        let initiator_addr = signer::address_of(account); // Get the initiator's address
        assert!(has_balance(initiator_addr, deposit), E_INSUFFICIENT_BALANCE); // Ensure user has enough balance for the deposit

        let agreement_id = generate_unique_agreement_id(account);  // Generate a unique agreement ID
        assert!(get_agreement(agreement_id) == None, E_AGREEMENT_ID_ALREADY_EXISTS); // Ensure the generated agreement ID doesn't exist

        lock_funds(account, agreement_id, deposit); // Lock funds from the initiator

        let agreement = Agreement {
            initiator: initiator_addr,
            responder: option::some(responder),
            initiator_deposit: deposit,
            responder_deposit: 0,
            expiration: expiration,
            is_completed: false,
            is_refundable: true,
            agreement_created_event: event::new_event_handle<AgreementCreatedEvent>(&mut signer),
            agreement_updated_event: event::new_event_handle<AgreementUpdatedEvent>(&mut signer),
            agreement_completed_event: event::new_event_handle<AgreementCompletedEvent>(&mut signer),
            agreement_cancelled_event: event::new_event_handle<AgreementCancelledEvent>(&mut signer),
        };

        let agreement_created_event_payload = AgreementCreatedEvent {
            agreement_id: agreement_id,
            initiator: initiator_addr,
            deposit: deposit,
            expiration: expiration,
        };

        event::emit_event(&mut agreement.agreement_created_event, agreement_created_event_payload); // Emit event
    }

    public fun agree_to_agreement(account: &signer, agreement_id: u64, deposit: u64) {
        let responder_addr = signer::address_of(account);
        assert!(has_balance(responder_addr, deposit), E_INSUFFICIENT_BALANCE); // Ensure user has enough balance for the deposit
        lock_funds(account, agreement_id, deposit); // Lock funds from the responder

        let agreement = get_agreement(agreement_id); // Retrieve agreement with agreement_id
        let current_time = get_current_timestamp();
        assert!(current_time <= agreement.expiration, E_AGREEMENT_EXPIRED); // Check the expiration after fetching the agreement

        agreement.responder = option::some(responder_addr); // Update agreement with responder address/deposit
        agreement.responder_deposit = deposit; // Update agreement with responder's deposit

        let agreement_updated_event_payload = AgreementUpdatedEvent {
            agreement_id: agreement_id,
            responder: responder_addr,
            deposit: deposit,
        };

        event::emit_event(&mut agreement.agreement_updated_event, agreement_updated_event_payload);
    }

    public fun complete_agreement(account: &signer, agreement_id: u64) {
        let initiator_addr = signer::address_of(account); // Retrieve the initiator's address
        let agreement = get_agreement(agreement_id); // Pull agreement

        let current_time = get_current_timestamp();
        assert!(current_time <= agreement.expiration, E_AGREEMENT_EXPIRED); // Check the expiration after fetching the agreement
        assert!(!agreement.is_completed, E_AGREEMENT_ALREADY_COMPLETED); // Ensure agreement is not already completed
        assert!(initiator_addr == agreement.initiator, E_INVALID_INITIATOR); // Ensure caller is the initiator
        assert!(agreement.responder.is_some(), E_RESPONDER_ALREADY_SIGNED); // Ensure agreement has a responder

        // Transfer funds to the responder
        transfer_funds(agreement.initiator, agreement.responder.unwrap(), agreement.initiator_deposit);

        // Set the agreement to completed
        agreement.is_completed = true;

        let agreement_completed_event_payload = AgreementCompletedEvent {
            agreement_id: agreement_id,
            responder: agreement.responder.unwrap(),
            deposit: agreement.initiator_deposit,
        };
        event::emit_event(&mut agreement.agreement_completed_event, agreement_completed_event_payload);
    }

    public fun cancel_agreement(account: &signer, agreement_id: u64) {
        let initiator_addr = signer::address_of(account);
        let agreement = get_agreement(agreement_id); // Pull agreement
        assert!(initiator_addr == agreement.initiator, E_INVALID_INITIATOR); // Ensure caller is the initiator
        assert!(agreement.responder.is_none(), E_RESPONDER_ALREADY_SIGNED); // Ensure responder did not sign

        let current_time = get_current_timestamp();
        assert!(current_time <= agreement.expiration, E_AGREEMENT_EXPIRED);
        assert!(!agreement.is_completed, E_AGREEMENT_ALREADY_COMPLETED);

        // Unlock and return funds to the initiator
        unlock_funds(agreement.initiator, agreement.initiator_deposit);

        let agreement_cancelled_event_payload = AgreementCancelledEvent {
            agreement_id: agreement_id,
            initiator: agreement.initiator,
            deposit: agreement.initiator_deposit,
        };
        event::emit_event(&mut agreement.agreement_cancelled_event, agreement_cancelled_event_payload);
    }
} 
