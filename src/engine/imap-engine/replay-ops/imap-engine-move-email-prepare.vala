/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.MoveEmailPrepare : Geary.ImapEngine.SendReplayOperation {
    public Gee.Set<ImapDB.EmailIdentifier>? prepared_for_move = null;
    
    private MinimalFolder engine;
    private Cancellable? cancellable;
    private Gee.List<ImapDB.EmailIdentifier> to_move = new Gee.ArrayList<ImapDB.EmailIdentifier>();
    
    public MoveEmailPrepare(MinimalFolder engine, Gee.Collection<ImapDB.EmailIdentifier> to_move,
        Cancellable? cancellable) {
        base.only_local("MoveEmailPrepare", OnError.RETRY);
        
        this.engine = engine;
        this.to_move.add_all(to_move);
        this.cancellable = cancellable;
    }
    
    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        if (prepared_for_move != null)
            prepared_for_move.remove_all(ids);
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        if (to_move.size <= 0)
            return ReplayOperation.Status.COMPLETED;
        
        int count = engine.get_remote_counts(null, null);
        
        // as this value is only used for reporting, offer best-possible service
        if (count < 0)
            count = to_move.size;
        
        prepared_for_move = yield engine.local_folder.mark_removed_async(to_move, true, cancellable);
        if (prepared_for_move == null || prepared_for_move.size == 0)
            return ReplayOperation.Status.COMPLETED;
        
        engine.replay_notify_email_removed(prepared_for_move);
        
        engine.replay_notify_email_count_changed(
            Numeric.int_floor(count - prepared_for_move.size, 0),
            Folder.CountChangeReason.REMOVED);
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids) {
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override async void backout_local_async() throws Error {
    }
    
    public override string describe_state() {
        return "%d email IDs".printf(prepared_for_move.size);
    }
}
