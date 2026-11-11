-- UniPlanner: improve RLS init-plan evaluation and cover unindexed foreign keys.
-- Additive only: no rows are changed or deleted; existing authorization predicates are preserved.

CREATE INDEX IF NOT EXISTS uniplanner_access_approved_by_idx ON public.uniplanner_access (approved_by);
CREATE INDEX IF NOT EXISTS uniplanner_group_messages_created_by_idx ON public.uniplanner_group_messages (created_by);
CREATE INDEX IF NOT EXISTS uniplanner_projects_created_by_idx ON public.uniplanner_projects (created_by);
CREATE INDEX IF NOT EXISTS uniplanner_shared_tasks_created_by_idx ON public.uniplanner_shared_tasks (created_by);
CREATE INDEX IF NOT EXISTS uniplanner_task_comments_created_by_idx ON public.uniplanner_task_comments (created_by);
CREATE INDEX IF NOT EXISTS uniplanner_task_comments_task_id_idx ON public.uniplanner_task_comments (task_id);
CREATE INDEX IF NOT EXISTS uniplanner_workspace_activity_actor_id_idx ON public.uniplanner_workspace_activity (actor_id);
CREATE INDEX IF NOT EXISTS uniplanner_workspace_invitations_invited_by_idx ON public.uniplanner_workspace_invitations (invited_by);
CREATE INDEX IF NOT EXISTS uniplanner_workspace_join_requests_reviewed_by_idx ON public.uniplanner_workspace_join_requests (reviewed_by);
CREATE INDEX IF NOT EXISTS uniplanner_workspace_join_requests_user_id_idx ON public.uniplanner_workspace_join_requests (user_id);
CREATE INDEX IF NOT EXISTS uniplanner_workspace_members_user_id_idx ON public.uniplanner_workspace_members (user_id);
CREATE INDEX IF NOT EXISTS uniplanner_workspace_notes_created_by_idx ON public.uniplanner_workspace_notes (created_by);
CREATE INDEX IF NOT EXISTS uniplanner_workspace_resources_created_by_idx ON public.uniplanner_workspace_resources (created_by);
CREATE INDEX IF NOT EXISTS uniplanner_workspaces_created_by_idx ON public.uniplanner_workspaces (created_by);

-- Hoist auth.uid() into an init plan where it is a statement-constant expression.
ALTER POLICY "Users can read their own access status" ON public.uniplanner_access USING ((user_id = (select auth.uid())));
ALTER POLICY "Users can delete their own UniPlanner data" ON public.uniplanner_data USING (((select auth.uid()) = user_id));
ALTER POLICY "Users can insert their own UniPlanner data" ON public.uniplanner_data WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "Users can read their own UniPlanner data" ON public.uniplanner_data USING (((select auth.uid()) = user_id));
ALTER POLICY "Users can update their own UniPlanner data" ON public.uniplanner_data USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "Authors or owners can delete group messages" ON public.uniplanner_group_messages USING (((created_by = (select auth.uid())) OR (EXISTS ( SELECT 1
   FROM uniplanner_workspace_members m
  WHERE ((m.workspace_id = uniplanner_group_messages.workspace_id) AND (m.user_id = (select auth.uid())) AND (m.role = 'owner'::text))))));
ALTER POLICY "Members can send group messages" ON public.uniplanner_group_messages WITH CHECK (((created_by = (select auth.uid())) AND uniplanner_is_workspace_member(workspace_id)));
ALTER POLICY "Users can create their own profile" ON public.uniplanner_profiles WITH CHECK ((user_id = (select auth.uid())));
ALTER POLICY "Users can read their own profile and workspace peers" ON public.uniplanner_profiles USING (((user_id = (select auth.uid())) OR (EXISTS ( SELECT 1
   FROM (uniplanner_workspace_members mine
     JOIN uniplanner_workspace_members peer ON ((peer.workspace_id = mine.workspace_id)))
  WHERE ((mine.user_id = (select auth.uid())) AND (peer.user_id = uniplanner_profiles.user_id))))));
ALTER POLICY "Users can update their own profile" ON public.uniplanner_profiles USING ((user_id = (select auth.uid()))) WITH CHECK ((user_id = (select auth.uid())));
ALTER POLICY "Creators or owners can delete projects" ON public.uniplanner_projects USING ((uniplanner_is_approved() AND ((created_by = (select auth.uid())) OR uniplanner_is_workspace_owner(workspace_id))));
ALTER POLICY "Workspace members can create projects" ON public.uniplanner_projects WITH CHECK ((uniplanner_is_approved() AND (created_by = (select auth.uid())) AND uniplanner_is_workspace_member(workspace_id)));
ALTER POLICY "Authors or owners can delete task comments" ON public.uniplanner_task_comments USING (((created_by = (select auth.uid())) OR (EXISTS ( SELECT 1
   FROM uniplanner_workspace_members m
  WHERE ((m.workspace_id = uniplanner_task_comments.workspace_id) AND (m.user_id = (select auth.uid())) AND (m.role = 'owner'::text))))));
ALTER POLICY "Members can add task comments" ON public.uniplanner_task_comments WITH CHECK (((created_by = (select auth.uid())) AND uniplanner_is_workspace_member(workspace_id) AND (EXISTS ( SELECT 1
   FROM uniplanner_shared_tasks t
  WHERE ((t.id = uniplanner_task_comments.task_id) AND (t.workspace_id = uniplanner_task_comments.workspace_id))))));
ALTER POLICY "Workspace owners and invitees can read invitations" ON public.uniplanner_workspace_invitations USING ((uniplanner_is_approved() AND (uniplanner_is_workspace_owner(workspace_id) OR (invited_user_id = (select auth.uid())) OR (lower(invited_email) = lower(COALESCE((auth.jwt() ->> 'email'::text), ''::text))))));
ALTER POLICY "Requesters and owners can read join requests" ON public.uniplanner_workspace_join_requests USING ((uniplanner_is_approved() AND ((user_id = (select auth.uid())) OR uniplanner_is_workspace_owner(workspace_id))));
ALTER POLICY "Requesters can cancel their own pending join requests" ON public.uniplanner_workspace_join_requests USING ((uniplanner_is_approved() AND (user_id = (select auth.uid())) AND (status = 'pending'::text))) WITH CHECK ((uniplanner_is_approved() AND (user_id = (select auth.uid())) AND (status = 'cancelled'::text)));
ALTER POLICY "Members can leave or owners can remove members" ON public.uniplanner_workspace_members USING ((((user_id = (select auth.uid())) AND (role <> 'owner'::text)) OR ((user_id <> (select auth.uid())) AND uniplanner_is_workspace_owner(workspace_id))));
ALTER POLICY "Authors or owners can delete shared notes" ON public.uniplanner_workspace_notes USING (((created_by = (select auth.uid())) OR (EXISTS ( SELECT 1
   FROM uniplanner_workspace_members m
  WHERE ((m.workspace_id = uniplanner_workspace_notes.workspace_id) AND (m.user_id = (select auth.uid())) AND (m.role = 'owner'::text))))));
ALTER POLICY "Members can add shared notes" ON public.uniplanner_workspace_notes WITH CHECK (((created_by = (select auth.uid())) AND uniplanner_is_workspace_member(workspace_id)));
ALTER POLICY "Creators or owners can delete resources" ON public.uniplanner_workspace_resources USING ((uniplanner_is_approved() AND ((created_by = (select auth.uid())) OR uniplanner_is_workspace_owner(workspace_id))));
ALTER POLICY "Workspace members can create resources" ON public.uniplanner_workspace_resources WITH CHECK ((uniplanner_is_approved() AND (created_by = (select auth.uid())) AND uniplanner_is_workspace_member(workspace_id)));
