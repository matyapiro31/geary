/* Copyright 2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.RevokableMove : Revokable {
    private GenericAccount account;
    private ImapEngine.MinimalFolder source;
    private FolderPath destination;
    private Gee.Set<ImapDB.EmailIdentifier> move_ids;
    
    public RevokableMove(GenericAccount account, ImapEngine.MinimalFolder source, FolderPath destination,
        Gee.Set<ImapDB.EmailIdentifier> move_ids) {
        this.account = account;
        this.source = source;
        this.destination = destination;
        this.move_ids = move_ids;
        
        account.folders_available_unavailable.connect(on_folders_available_unavailable);
        source.email_removed.connect(on_source_email_removed);
        source.closing.connect(on_source_closing);
    }
    
    ~RevokableMove() {
        account.folders_available_unavailable.disconnect(on_folders_available_unavailable);
        source.email_removed.disconnect(on_source_email_removed);
        source.closing.disconnect(on_source_closing);
        
        // if still valid, schedule operation so its executed
        if (valid) {
            debug("Freeing revokable, scheduling move %d emails from %s to %s", move_ids.size,
                source.path.to_string(), destination.to_string());
            
            try {
                source.schedule_op(new MoveEmailCommit(source, move_ids, destination, null));
            } catch (Error err) {
                debug("Move from %s to %s failed: %s", source.path.to_string(), destination.to_string(),
                    err.message);
            }
        }
    }
    
    protected override async void internal_revoke_async(Cancellable? cancellable) throws Error {
        try {
            yield source.exec_op_async(new MoveEmailRevoke(source, move_ids, cancellable),
                cancellable);
        } finally {
            valid = false;
        }
    }
    
    protected override async void internal_commit_async(Cancellable? cancellable) throws Error {
        try {
            yield source.exec_op_async(new MoveEmailCommit(source, move_ids, destination, cancellable),
                cancellable);
        } finally {
            valid = false;
        }
    }
    
    private void on_folders_available_unavailable(Gee.List<Folder>? available, Gee.List<Folder>? unavailable) {
        // look for either of the folders going away
        if (unavailable != null) {
            foreach (Folder folder in unavailable) {
                if (folder.path.equal_to(source.path) || folder.path.equal_to(destination)) {
                    valid = false;
                    
                    break;
                }
            }
        }
    }
    
    private void on_source_email_removed(Gee.Collection<EmailIdentifier> ids) {
        // one-way switch, and only interested in destination folder activity
        if (!valid)
            return;
        
        foreach (EmailIdentifier id in ids)
            move_ids.remove((ImapDB.EmailIdentifier) id);
        
        valid = move_ids.size > 0;
    }
    
    private void on_source_closing(Gee.List<ReplayOperation> final_ops) {
        if (valid)
            final_ops.add(new MoveEmailCommit(source, move_ids, destination, null));
    }
}
