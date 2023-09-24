module escrow_address::escrow {

    // This module implements an escrow agreement between two parties.
    // The agreement is created by the initiator, who locks funds in the escrow account.
    // The responder can then agree to the agreement by locking funds in the escrow account.
    // The initiator can then complete the agreement, which transfers the funds to the responder.
    // The initiator can cancel the agreement if the responder has not agreed to the agreement.
    // The agreement expires if the responder does not agree to the agreement within the expiration time.

    // The agreement is stored in the AgreementStore resource.
    // The AgreementStore resource contains a vector of Agreement resources.
    // The Agreement resource contains the details of the agreement.
    // The Agreement resource also contains event handles to emit events.

    use aptos_framework::account;
    use aptos_framework::event;
    use std::signer;
    use std::vector;
    use std::string::String;
    use 0x1::Signer;
    use 0x1::Balance;

    #[test_only]
    use std::string;

    // error codes
    const E_NOT_INITIALIZED: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    const E_AGREEMENT_EXPIRED: u64 = 3;
    const E_AGREEMENT_ALREADY_COMPLETED: u64 = 4;
    const E_AGREEMENT_NOT_EXPIRED: u64 = 5;
    const E_AGREEMENT_ID_ALREADY_EXISTS: u64 = 6;

    // resource for storing agreements
    resource struct AgreementStore { // Resource to store agreements
        agreements: vector,
    }

    // main structs - Agreement and AgreementCounter
    struct Agreement has key { 
        initiator: address,         
        responder: option::Option<address>,  
        initiator_deposit: u64,    
        responder_deposit: u64,    
        expiration: u64,
        is_completed: bool,

        agreement_created_event: event::EventHandle<AgreementCreatedEvent>,
        agreement_updated_event: event::EventHandle<AgreementUpdatedEvent>,
        agreement_completed_event: event::EventHandle<AgreementCompletedEvent>,
        agreement_cancelled_event: event::EventHandle<AgreementCancelledEvent>,
    }
    struct AgreementCounter {
    count: u64,
    }

    // event structs
    struct AgreementCreatedEvent { // Agreement created event
        agreement_id: u64,
        initiator: address,
        deposit: u64,
        expiration: u64,
    }
    struct AgreementUpdatedEvent { // Agreement updated event
        agreement_id: u64,
        responder: address,
        deposit: u64,
    }
    struct AgreementCompletedEvent { // Agreement completed event
        agreement_id: u64,
        responder: address,
        deposit: u64,
    }
    struct AgreementCancelledEvent { // Agreement cancelled event
        agreement_id: u64,
        initiator: address,
        deposit: u64,
    }

    // background functions (13)
    public fun initialize_agreement_store() { // 1
        move_to(0x1, AgreementStore { agreements: vector::new() });
    }
    public fun initialize_agreement_counter(account: &amp;signer) { // 2
        move_to(account, AgreementCounter { count: 0 });
    }
    public fun get_agreement_store() -&gt; &amp;mut AgreementStore { // 3
        let store: &amp;mut AgreementStore = &amp;mut move_from(0x1);
        return store;
    }
    public fun get_escrow_account() -&gt; address { // 4
        let store: &amp;mut AgreementStore = &amp;mut move_from(0x1);
        let escrow_account = store.agreements<a title="0" class="supContainer"><sup>1</sup></a>;
        return escrow_account;
    }
    public fun generate_unique_agreement_id(account: &amp;signer) -&gt; u64 { // 5
        let addr = signer::address_of(account);
        let counter = borrow_global_mut(addr);
        counter.count = counter.count + 1;
        counter.count
    }
    public fun get_current_timestamp() -&gt; u64 { // 6
        let sender = Signer::get_txn_sender();
        let current_block = Signer::get_block_metadata();
        let current_timestamp = current_block.timestamp;
        return current_timestamp;
    }
    public fun has_balance(account_addr: address, amount: u64) -&gt; bool { // 7
        let balance: &amp;Balance.T = &amp;move_from(account_addr);
        let account_balance: u64 = *balance;
        return account_balance &gt;= amount;
    }
    public fun transfer_funds(from: address, to: address, amount: u64) { // 8
        let sender = Signer::get_txn_sender();
        assert(from == sender, 77); // Ensure the sender is the same as the 'from' account

        let from_balance: &amp;mut Balance.T = &amp;mut move_from(from);
        let to_balance: &amp;mut Balance.T = &amp;mut move_from(to);

        assert(*from_balance &gt;= amount, 78); // Ensure the 'from' account has enough balance

        *from_balance -= amount;
        *to_balance += amount;

        move_to_sender(from_balance);
        move_to_sender(to_balance);
    }
    public fun unlock_funds(account_addr: address, amount: u64) { // 9
        let sender = Signer::get_txn_sender();
        assert(account_addr != sender, 77); // Ensure the account is not the sender's account

        let account_balance: &amp;mut Balance.T = &amp;mut move_from(account_addr);
        let sender_balance: &amp;mut Balance.T = &amp;mut move_from(sender);

        assert(*account_balance &gt;= amount, 78); // Ensure the account has enough balance

        *account_balance -= amount;
        *sender_balance += amount;

        move_to_sender(account_balance);
        move_to_sender(sender_balance);
    }
    public fun get_agreement(agreement_id: u64) -&gt; &amp;mut Agreement { // 10
        let store: &amp;mut AgreementStore = &amp;mut move_from(0x1);
        let agreement: &amp;mut Agreement = &amp;mut store.agreements<a title="agreement_id as usize" class="supContainer"><sup>1</sup></a>;
        return agreement;
    }
    public fun update_agreement(agreement_id: u64, agreement: &amp;mut Agreement) { // 11
        let store: &amp;mut AgreementStore = &amp;mut move_from(0x1);
        let existing_agreement: &amp;mut Agreement = &amp;mut store.agreements<a title="agreement_id as usize" class="supContainer"><sup>1</sup></a>;
        *existing_agreement = *agreement;
    }
    public fun expire_agreement(agreement_id: u64) { // 12
        let agreement = get_agreement(agreement_id);
        let current_time = get_current_timestamp();
        assert!(current_time &gt; agreement.expiration, E_AGREEMENT_NOT_EXPIRED);
        assert!(!agreement.is_completed, E_AGREEMENT_ALREADY_COMPLETED);
        
        if agreement.is_refundable {
            unlock_funds(agreement.initiator, agreement.initiator_deposit);
        } else {
            // Could handle non-refundable agreement expiration logic here
        }
        emit AgreementExpired(agreement_id);
    }
    public fun lock_funds(account: &amp;signer, agreement_id: u64, amount: u64) {
        let initiator_addr = signer::address_of(account);
        let agreement = get_agreement(agreement_id); // Pull agreement
        assert!(initiator_addr == agreement.initiator, E_INVALID_INITIATOR); // Make sure caller is the initiator
        assert!(agreement.responder.is_none(), E_RESPONDER_ALREADY_SIGNED); // Make sure responder hasn't signed agreement yet

        let escrow_account = get_escrow_account(); // Get the address of the escrow account
        transfer(initiator_addr, escrow_account, amount); // Transfer funds from the initiator to the escrow account

        // Update the agreement to reflect the locked funds
        agreement.initiator_deposit = amount;
        update_agreement(agreement_id, agreement);
    }

// double check this

    // User functions
    public fun create_escrow(account: &signer, deposit: u64, expiration: u64, responder: address) {
        
        let initiator_addr = signer::address_of(account); // Get the initiator's address
        assert!(has_balance(initiator_addr, deposit), E_INSUFFICIENT_BALANCE); // Make sure user has enough balance for the deposit
        
        let agreement_id = generate_unique_agreement_id(account);  // Generate a unique agreement ID
        assert!(get_agreement(agreement_id) == None, E_AGREEMENT_ID_ALREADY_EXISTS); // Make sure the generated agreement ID doesn't exist

        lock_funds(account, agreement_id, deposit); // Lock funds from the initiator

        let agreement = Agreement { // Create the agreement
            initiator: initiator_addr,
            responder: option::some(responder),
            initiator_deposit: deposit,
            responder_deposit: 0,
            expiration: expiration,
        };

        let agreement_created_event_payload = AgreementCreatedEvent { // Event details
            agreement_id: agreement_id,
            initiator: initiator_addr,
            deposit: deposit,
            expiration: expiration,
        };

        event::emit_event(&mut agreement.agreement_created_event, agreement_created_event_payload); // Emit event
    }
    public fun agree_to_agreement(account: &signer, agreement_id: u64, deposit: u64) {
        let responder_addr = signer::address_of(account);
        assert!(has_balance(responder_addr, deposit), 2); // Make sure user has enough balance for the deposit
        lock_funds(responder_addr, deposit); // Lock funds from the responder

        let agreement = get_agreement(agreement_id); // Get agreement with agreement_id
        let current_time = get_current_timestamp();
        assert!(current_time <= agreement.expiration, E_AGREEMENT_EXPIRED); // Check the expiration after fetching the agreement

        agreement.responder = option::some(responder_addr); // Update agreement with responder address/deposit
        agreement.responder_deposit = deposit; // Update agreement with responder's deposit

        let agreement_updated_event_payload = AgreementUpdatedEvent { // Event
            agreement_id: agreement_id,
            responder: responder_addr,
            deposit: deposit,
        };

        event::emit_event(&mut agreement.agreement_updated_event, agreement_updated_event_payload);
    }
    public fun complete_agreement(account: &amp;signer, agreement_id: u64) {
        let initiator_addr = signer::address_of(account); // Get the initiator's address
        let agreement = get_agreement(agreement_id); // Pull agreement

        let current_time = get_current_timestamp();
        assert!(current_time &lt;= agreement.expiration, E_AGREEMENT_EXPIRED); // Check the expiration after fetching the agreement
        assert!(!agreement.is_completed, E_AGREEMENT_ALREADY_COMPLETED); // Make sure agreement is not already completed
        assert!(initiator_addr == agreement.initiator, 3); // Make sure caller is the initiator
        assert!(agreement.responder.is_some(), 4); // Make sure agreement has a responder

        // Transfer funds to the responder
        transfer_funds(agreement.initiator, agreement.responder.unwrap(), agreement.initiator_deposit);

        // Set the agreement to completed
        agreement.is_completed = true;

        let agreement_completed_event_payload = AgreementCompletedEvent { // Event
            agreement_id: agreement_id, 
            responder: agreement.responder.unwrap(), 
            deposit: agreement.initiator_deposit, 
        };
        event::emit_event(&amp;mut agreement.agreement_completed_event, agreement_completed_event_payload);
    }
    public fun cancel_agreement(account: &signer, agreement_id: u64) {
        let initiator_addr = signer::address_of(account);
        let agreement = get_agreement(agreement_id); // Pull agreement
        assert!(initiator_addr == agreement.initiator, 3); // Make sure caller is the initiator
        assert!(agreement.responder.is_none(), 4); // Make sure responder did not sign

        let current_time = get_current_timestamp();
        assert!(current_time <= agreement.expiration, E_AGREEMENT_EXPIRED);
        assert!(!agreement.is_completed, E_AGREEMENT_ALREADY_COMPLETED);

        // Unlock and return funds to the initiator
        unlock_funds(agreement.initiator, agreement.initiator_deposit);

        let agreement_cancelled_event_payload = AgreementCancelledEvent { // Event
            agreement_id: agreement_id,
            initiator: agreement.initiator,
            deposit: agreement.initiator_deposit,
        };
        event::emit_event(&mut agreement.agreement_cancelled_event, agreement_cancelled_event_payload);
    }

}