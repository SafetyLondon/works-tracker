export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      actions: {
        Row: {
          assignee_id: string | null
          cancelled_at: string | null
          cleaning_visit_id: string | null
          closed_at: string | null
          created_at: string
          created_by: string | null
          description: string | null
          due_date: string | null
          id: string
          priority: Database["public"]["Enums"]["action_priority"]
          scope_classification: Database["public"]["Enums"]["scope_classification"]
          site_id: string
          source_constraint_id: string | null
          source_focus_item_score_id: string | null
          source_review_line_score_id: string | null
          status: Database["public"]["Enums"]["action_status"]
          title: string
          updated_at: string
          urgent_hs_flag: boolean
          verification_note: string | null
          version_no: number
        }
        Insert: {
          assignee_id?: string | null
          cancelled_at?: string | null
          cleaning_visit_id?: string | null
          closed_at?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          due_date?: string | null
          id?: string
          priority?: Database["public"]["Enums"]["action_priority"]
          scope_classification: Database["public"]["Enums"]["scope_classification"]
          site_id: string
          source_constraint_id?: string | null
          source_focus_item_score_id?: string | null
          source_review_line_score_id?: string | null
          status?: Database["public"]["Enums"]["action_status"]
          title: string
          updated_at?: string
          urgent_hs_flag?: boolean
          verification_note?: string | null
          version_no?: number
        }
        Update: {
          assignee_id?: string | null
          cancelled_at?: string | null
          cleaning_visit_id?: string | null
          closed_at?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          due_date?: string | null
          id?: string
          priority?: Database["public"]["Enums"]["action_priority"]
          scope_classification?: Database["public"]["Enums"]["scope_classification"]
          site_id?: string
          source_constraint_id?: string | null
          source_focus_item_score_id?: string | null
          source_review_line_score_id?: string | null
          status?: Database["public"]["Enums"]["action_status"]
          title?: string
          updated_at?: string
          urgent_hs_flag?: boolean
          verification_note?: string | null
          version_no?: number
        }
        Relationships: [
          {
            foreignKeyName: "actions_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "actions_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "v_dashboard_counters"
            referencedColumns: ["site_id"]
          },
          {
            foreignKeyName: "actions_source_constraint_id_fkey"
            columns: ["source_constraint_id"]
            isOneToOne: false
            referencedRelation: "visit_constraints"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "actions_source_focus_item_score_id_fkey"
            columns: ["source_focus_item_score_id"]
            isOneToOne: false
            referencedRelation: "focus_item_scores"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "actions_source_review_line_score_id_fkey"
            columns: ["source_review_line_score_id"]
            isOneToOne: false
            referencedRelation: "review_line_scores"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "actions_visit_site_fk"
            columns: ["cleaning_visit_id", "site_id"]
            isOneToOne: false
            referencedRelation: "cleaning_visits"
            referencedColumns: ["id", "site_id"]
          },
        ]
      }
      activity_log: {
        Row: {
          action: string
          actor_id: string | null
          created_at: string
          detail: Json | null
          entity_id: string
          entity_kind: string
          id: number
          site_id: string | null
        }
        Insert: {
          action: string
          actor_id?: string | null
          created_at?: string
          detail?: Json | null
          entity_id: string
          entity_kind: string
          id?: number
          site_id?: string | null
        }
        Update: {
          action?: string
          actor_id?: string | null
          created_at?: string
          detail?: Json | null
          entity_id?: string
          entity_kind?: string
          id?: number
          site_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "activity_log_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_log_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "v_dashboard_counters"
            referencedColumns: ["site_id"]
          },
        ]
      }
      cleaning_visits: {
        Row: {
          cancelled_at: string | null
          closed_at: string | null
          created_at: string
          created_by: string | null
          headcount: number | null
          id: string
          notes: string | null
          recommended_rotation_week: number | null
          reviewed_at: string | null
          rotation_programme_id: string | null
          rotation_week_override: number | null
          rotation_week_override_reason: string | null
          site_id: string
          status: Database["public"]["Enums"]["cleaning_visit_status"]
          submitted_at: string | null
          submitted_by: string | null
          supervisor_id: string | null
          updated_at: string
          version_no: number
          visit_date: string
          visit_template_id: string
          weather: string | null
          weekday_override_reason: string | null
        }
        Insert: {
          cancelled_at?: string | null
          closed_at?: string | null
          created_at?: string
          created_by?: string | null
          headcount?: number | null
          id?: string
          notes?: string | null
          recommended_rotation_week?: number | null
          reviewed_at?: string | null
          rotation_programme_id?: string | null
          rotation_week_override?: number | null
          rotation_week_override_reason?: string | null
          site_id: string
          status?: Database["public"]["Enums"]["cleaning_visit_status"]
          submitted_at?: string | null
          submitted_by?: string | null
          supervisor_id?: string | null
          updated_at?: string
          version_no?: number
          visit_date: string
          visit_template_id: string
          weather?: string | null
          weekday_override_reason?: string | null
        }
        Update: {
          cancelled_at?: string | null
          closed_at?: string | null
          created_at?: string
          created_by?: string | null
          headcount?: number | null
          id?: string
          notes?: string | null
          recommended_rotation_week?: number | null
          reviewed_at?: string | null
          rotation_programme_id?: string | null
          rotation_week_override?: number | null
          rotation_week_override_reason?: string | null
          site_id?: string
          status?: Database["public"]["Enums"]["cleaning_visit_status"]
          submitted_at?: string | null
          submitted_by?: string | null
          supervisor_id?: string | null
          updated_at?: string
          version_no?: number
          visit_date?: string
          visit_template_id?: string
          weather?: string | null
          weekday_override_reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "cleaning_visits_rotation_programme_id_fkey"
            columns: ["rotation_programme_id"]
            isOneToOne: false
            referencedRelation: "rotation_programmes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cleaning_visits_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cleaning_visits_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "v_dashboard_counters"
            referencedColumns: ["site_id"]
          },
          {
            foreignKeyName: "cleaning_visits_visit_template_id_fkey"
            columns: ["visit_template_id"]
            isOneToOne: false
            referencedRelation: "visit_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      constraint_types: {
        Row: {
          code: string
          created_at: string
          description: string | null
          is_active: boolean
          label: string
          sort_order: number
        }
        Insert: {
          code: string
          created_at?: string
          description?: string | null
          is_active?: boolean
          label: string
          sort_order?: number
        }
        Update: {
          code?: string
          created_at?: string
          description?: string | null
          is_active?: boolean
          label?: string
          sort_order?: number
        }
        Relationships: []
      }
      evidence_items: {
        Row: {
          bucket: string
          byte_size: number | null
          created_at: string
          id: string
          mime_type: string | null
          site_id: string
          storage_path: string
          uploaded_by: string | null
        }
        Insert: {
          bucket?: string
          byte_size?: number | null
          created_at?: string
          id?: string
          mime_type?: string | null
          site_id: string
          storage_path: string
          uploaded_by?: string | null
        }
        Update: {
          bucket?: string
          byte_size?: number | null
          created_at?: string
          id?: string
          mime_type?: string | null
          site_id?: string
          storage_path?: string
          uploaded_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "evidence_items_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "evidence_items_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "v_dashboard_counters"
            referencedColumns: ["site_id"]
          },
        ]
      }
      focus_categories: {
        Row: {
          archived_at: string | null
          code: string
          created_at: string
          display_order: number
          id: string
          label: string
          site_id: string
        }
        Insert: {
          archived_at?: string | null
          code: string
          created_at?: string
          display_order?: number
          id?: string
          label: string
          site_id: string
        }
        Update: {
          archived_at?: string | null
          code?: string
          created_at?: string
          display_order?: number
          id?: string
          label?: string
          site_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "focus_categories_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "focus_categories_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "v_dashboard_counters"
            referencedColumns: ["site_id"]
          },
        ]
      }
      focus_item_score_evidence: {
        Row: {
          caption: string | null
          created_at: string
          evidence_item_id: string
          focus_item_score_id: string
        }
        Insert: {
          caption?: string | null
          created_at?: string
          evidence_item_id: string
          focus_item_score_id: string
        }
        Update: {
          caption?: string | null
          created_at?: string
          evidence_item_id?: string
          focus_item_score_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "focus_item_score_evidence_evidence_item_id_fkey"
            columns: ["evidence_item_id"]
            isOneToOne: false
            referencedRelation: "evidence_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "focus_item_score_evidence_focus_item_score_id_fkey"
            columns: ["focus_item_score_id"]
            isOneToOne: false
            referencedRelation: "focus_item_scores"
            referencedColumns: ["id"]
          },
        ]
      }
      focus_item_scores: {
        Row: {
          cleaning_visit_id: string
          comment: string | null
          created_at: string
          focus_acceptance_snapshot: string | null
          focus_label_snapshot: string | null
          focus_location_snapshot: string | null
          id: string
          is_failure: boolean | null
          is_na: boolean
          issue_type_code: string | null
          na_reason: string | null
          rating: number | null
          rating_band_display: string | null
          review_id: string
          scope_classification:
            | Database["public"]["Enums"]["scope_classification"]
            | null
          urgent_hs_flag: boolean
          visit_focus_item_id: string
        }
        Insert: {
          cleaning_visit_id: string
          comment?: string | null
          created_at?: string
          focus_acceptance_snapshot?: string | null
          focus_label_snapshot?: string | null
          focus_location_snapshot?: string | null
          id?: string
          is_failure?: boolean | null
          is_na?: boolean
          issue_type_code?: string | null
          na_reason?: string | null
          rating?: number | null
          rating_band_display?: string | null
          review_id: string
          scope_classification?:
            | Database["public"]["Enums"]["scope_classification"]
            | null
          urgent_hs_flag?: boolean
          visit_focus_item_id: string
        }
        Update: {
          cleaning_visit_id?: string
          comment?: string | null
          created_at?: string
          focus_acceptance_snapshot?: string | null
          focus_label_snapshot?: string | null
          focus_location_snapshot?: string | null
          id?: string
          is_failure?: boolean | null
          is_na?: boolean
          issue_type_code?: string | null
          na_reason?: string | null
          rating?: number | null
          rating_band_display?: string | null
          review_id?: string
          scope_classification?:
            | Database["public"]["Enums"]["scope_classification"]
            | null
          urgent_hs_flag?: boolean
          visit_focus_item_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "fis_focus_item_visit_fk"
            columns: ["visit_focus_item_id", "cleaning_visit_id"]
            isOneToOne: false
            referencedRelation: "visit_focus_items"
            referencedColumns: ["id", "cleaning_visit_id"]
          },
          {
            foreignKeyName: "fis_review_visit_fk"
            columns: ["review_id", "cleaning_visit_id"]
            isOneToOne: false
            referencedRelation: "reviews"
            referencedColumns: ["id", "cleaning_visit_id"]
          },
          {
            foreignKeyName: "focus_item_scores_issue_type_code_fkey"
            columns: ["issue_type_code"]
            isOneToOne: false
            referencedRelation: "issue_types"
            referencedColumns: ["code"]
          },
        ]
      }
      focus_items: {
        Row: {
          acceptance_standard: string | null
          archived_at: string | null
          category_id: string | null
          code: string
          created_at: string
          description: string | null
          display_order: number
          exact_location_required: boolean
          id: string
          label: string
          site_id: string
          visit_template_id: string | null
        }
        Insert: {
          acceptance_standard?: string | null
          archived_at?: string | null
          category_id?: string | null
          code: string
          created_at?: string
          description?: string | null
          display_order?: number
          exact_location_required?: boolean
          id?: string
          label: string
          site_id: string
          visit_template_id?: string | null
        }
        Update: {
          acceptance_standard?: string | null
          archived_at?: string | null
          category_id?: string | null
          code?: string
          created_at?: string
          description?: string | null
          display_order?: number
          exact_location_required?: boolean
          id?: string
          label?: string
          site_id?: string
          visit_template_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "focus_items_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "focus_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "focus_items_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "focus_items_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "v_dashboard_counters"
            referencedColumns: ["site_id"]
          },
          {
            foreignKeyName: "focus_items_visit_template_id_fkey"
            columns: ["visit_template_id"]
            isOneToOne: false
            referencedRelation: "visit_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      issue_types: {
        Row: {
          code: string
          created_at: string
          description: string | null
          is_active: boolean
          label: string
          sort_order: number
        }
        Insert: {
          code: string
          created_at?: string
          description?: string | null
          is_active?: boolean
          label: string
          sort_order?: number
        }
        Update: {
          code?: string
          created_at?: string
          description?: string | null
          is_active?: boolean
          label?: string
          sort_order?: number
        }
        Relationships: []
      }
      profiles: {
        Row: {
          created_at: string
          disabled_at: string | null
          disabled_by: string | null
          display_name: string | null
          email: string | null
          id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          disabled_at?: string | null
          disabled_by?: string | null
          display_name?: string | null
          email?: string | null
          id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          disabled_at?: string | null
          disabled_by?: string | null
          display_name?: string | null
          email?: string | null
          id?: string
          updated_at?: string
        }
        Relationships: []
      }
      review_line_score_evidence: {
        Row: {
          caption: string | null
          created_at: string
          evidence_item_id: string
          review_line_score_id: string
        }
        Insert: {
          caption?: string | null
          created_at?: string
          evidence_item_id: string
          review_line_score_id: string
        }
        Update: {
          caption?: string | null
          created_at?: string
          evidence_item_id?: string
          review_line_score_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "review_line_score_evidence_evidence_item_id_fkey"
            columns: ["evidence_item_id"]
            isOneToOne: false
            referencedRelation: "evidence_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "review_line_score_evidence_review_line_score_id_fkey"
            columns: ["review_line_score_id"]
            isOneToOne: false
            referencedRelation: "review_line_scores"
            referencedColumns: ["id"]
          },
        ]
      }
      review_line_scores: {
        Row: {
          cleaning_visit_id: string
          comment: string | null
          created_at: string
          id: string
          is_failure: boolean | null
          is_na: boolean
          issue_type_code: string | null
          line_label_snapshot: string | null
          na_reason: string | null
          rating: number | null
          rating_band_display: string | null
          review_id: string
          scope_classification:
            | Database["public"]["Enums"]["scope_classification"]
            | null
          urgent_hs_flag: boolean
          visit_rating_line_id: string
        }
        Insert: {
          cleaning_visit_id: string
          comment?: string | null
          created_at?: string
          id?: string
          is_failure?: boolean | null
          is_na?: boolean
          issue_type_code?: string | null
          line_label_snapshot?: string | null
          na_reason?: string | null
          rating?: number | null
          rating_band_display?: string | null
          review_id: string
          scope_classification?:
            | Database["public"]["Enums"]["scope_classification"]
            | null
          urgent_hs_flag?: boolean
          visit_rating_line_id: string
        }
        Update: {
          cleaning_visit_id?: string
          comment?: string | null
          created_at?: string
          id?: string
          is_failure?: boolean | null
          is_na?: boolean
          issue_type_code?: string | null
          line_label_snapshot?: string | null
          na_reason?: string | null
          rating?: number | null
          rating_band_display?: string | null
          review_id?: string
          scope_classification?:
            | Database["public"]["Enums"]["scope_classification"]
            | null
          urgent_hs_flag?: boolean
          visit_rating_line_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "review_line_scores_issue_type_code_fkey"
            columns: ["issue_type_code"]
            isOneToOne: false
            referencedRelation: "issue_types"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "rls_rating_line_visit_fk"
            columns: ["visit_rating_line_id", "cleaning_visit_id"]
            isOneToOne: false
            referencedRelation: "visit_rating_lines"
            referencedColumns: ["id", "cleaning_visit_id"]
          },
          {
            foreignKeyName: "rls_review_visit_fk"
            columns: ["review_id", "cleaning_visit_id"]
            isOneToOne: false
            referencedRelation: "reviews"
            referencedColumns: ["id", "cleaning_visit_id"]
          },
        ]
      }
      reviews: {
        Row: {
          cleaning_visit_id: string
          created_at: string
          general_comment: string | null
          id: string
          review_type: Database["public"]["Enums"]["review_type"]
          reviewer_id: string | null
          status: Database["public"]["Enums"]["review_status"]
          submitted_at: string | null
          superseded_at: string | null
          superseded_by_review_id: string | null
          supersedes_review_id: string | null
          updated_at: string
          urgent_hs_detail: string | null
          urgent_hs_flag: boolean
          urgent_source_constraint_id: string | null
          version_no: number
        }
        Insert: {
          cleaning_visit_id: string
          created_at?: string
          general_comment?: string | null
          id?: string
          review_type?: Database["public"]["Enums"]["review_type"]
          reviewer_id?: string | null
          status?: Database["public"]["Enums"]["review_status"]
          submitted_at?: string | null
          superseded_at?: string | null
          superseded_by_review_id?: string | null
          supersedes_review_id?: string | null
          updated_at?: string
          urgent_hs_detail?: string | null
          urgent_hs_flag?: boolean
          urgent_source_constraint_id?: string | null
          version_no?: number
        }
        Update: {
          cleaning_visit_id?: string
          created_at?: string
          general_comment?: string | null
          id?: string
          review_type?: Database["public"]["Enums"]["review_type"]
          reviewer_id?: string | null
          status?: Database["public"]["Enums"]["review_status"]
          submitted_at?: string | null
          superseded_at?: string | null
          superseded_by_review_id?: string | null
          supersedes_review_id?: string | null
          updated_at?: string
          urgent_hs_detail?: string | null
          urgent_hs_flag?: boolean
          urgent_source_constraint_id?: string | null
          version_no?: number
        }
        Relationships: [
          {
            foreignKeyName: "reviews_cleaning_visit_id_fkey"
            columns: ["cleaning_visit_id"]
            isOneToOne: false
            referencedRelation: "cleaning_visits"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reviews_superseded_by_review_id_fkey"
            columns: ["superseded_by_review_id"]
            isOneToOne: false
            referencedRelation: "reviews"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reviews_supersedes_review_id_fkey"
            columns: ["supersedes_review_id"]
            isOneToOne: false
            referencedRelation: "reviews"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reviews_urgent_source_constraint_id_fkey"
            columns: ["urgent_source_constraint_id"]
            isOneToOne: false
            referencedRelation: "visit_constraints"
            referencedColumns: ["id"]
          },
        ]
      }
      role_definitions: {
        Row: {
          code: string
          created_at: string
          description: string | null
          is_active: boolean
          is_global: boolean
          label: string
          sort_order: number
        }
        Insert: {
          code: string
          created_at?: string
          description?: string | null
          is_active?: boolean
          is_global?: boolean
          label: string
          sort_order?: number
        }
        Update: {
          code?: string
          created_at?: string
          description?: string | null
          is_active?: boolean
          is_global?: boolean
          label?: string
          sort_order?: number
        }
        Relationships: []
      }
      rotation_programmes: {
        Row: {
          anchor_date: string | null
          archived_at: string | null
          code: string
          created_at: string
          cycle_length_weeks: number
          id: string
          name: string
          site_id: string
          updated_at: string
          visit_template_id: string
        }
        Insert: {
          anchor_date?: string | null
          archived_at?: string | null
          code: string
          created_at?: string
          cycle_length_weeks: number
          id?: string
          name: string
          site_id: string
          updated_at?: string
          visit_template_id: string
        }
        Update: {
          anchor_date?: string | null
          archived_at?: string | null
          code?: string
          created_at?: string
          cycle_length_weeks?: number
          id?: string
          name?: string
          site_id?: string
          updated_at?: string
          visit_template_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "rotation_programmes_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rotation_programmes_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "v_dashboard_counters"
            referencedColumns: ["site_id"]
          },
          {
            foreignKeyName: "rotation_programmes_visit_template_id_fkey"
            columns: ["visit_template_id"]
            isOneToOne: false
            referencedRelation: "visit_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      rotation_step_focus_items: {
        Row: {
          created_at: string
          display_order: number
          focus_item_id: string
          id: string
          rotation_step_id: string
        }
        Insert: {
          created_at?: string
          display_order?: number
          focus_item_id: string
          id?: string
          rotation_step_id: string
        }
        Update: {
          created_at?: string
          display_order?: number
          focus_item_id?: string
          id?: string
          rotation_step_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "rotation_step_focus_items_focus_item_id_fkey"
            columns: ["focus_item_id"]
            isOneToOne: false
            referencedRelation: "focus_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rotation_step_focus_items_rotation_step_id_fkey"
            columns: ["rotation_step_id"]
            isOneToOne: false
            referencedRelation: "rotation_steps"
            referencedColumns: ["id"]
          },
        ]
      }
      rotation_steps: {
        Row: {
          archived_at: string | null
          created_at: string
          description: string | null
          display_order: number
          id: string
          rotation_programme_id: string
          title: string
          week_number: number
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          description?: string | null
          display_order?: number
          id?: string
          rotation_programme_id: string
          title: string
          week_number: number
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          description?: string | null
          display_order?: number
          id?: string
          rotation_programme_id?: string
          title?: string
          week_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "rotation_steps_rotation_programme_id_fkey"
            columns: ["rotation_programme_id"]
            isOneToOne: false
            referencedRelation: "rotation_programmes"
            referencedColumns: ["id"]
          },
        ]
      }
      sites: {
        Row: {
          archived_at: string | null
          archived_by: string | null
          code: string
          created_at: string
          id: string
          name: string
          timezone: string
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          archived_by?: string | null
          code: string
          created_at?: string
          id?: string
          name: string
          timezone?: string
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          archived_by?: string | null
          code?: string
          created_at?: string
          id?: string
          name?: string
          timezone?: string
          updated_at?: string
        }
        Relationships: []
      }
      template_rating_lines: {
        Row: {
          archived_at: string | null
          code: string
          created_at: string
          description: string | null
          display_order: number
          id: string
          label: string
          visit_template_id: string
        }
        Insert: {
          archived_at?: string | null
          code: string
          created_at?: string
          description?: string | null
          display_order?: number
          id?: string
          label: string
          visit_template_id: string
        }
        Update: {
          archived_at?: string | null
          code?: string
          created_at?: string
          description?: string | null
          display_order?: number
          id?: string
          label?: string
          visit_template_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "template_rating_lines_visit_template_id_fkey"
            columns: ["visit_template_id"]
            isOneToOne: false
            referencedRelation: "visit_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      template_scope_items: {
        Row: {
          archived_at: string | null
          code: string
          created_at: string
          description: string | null
          display_order: number
          id: string
          item_type: string
          label: string
          visit_template_id: string
        }
        Insert: {
          archived_at?: string | null
          code: string
          created_at?: string
          description?: string | null
          display_order?: number
          id?: string
          item_type: string
          label: string
          visit_template_id: string
        }
        Update: {
          archived_at?: string | null
          code?: string
          created_at?: string
          description?: string | null
          display_order?: number
          id?: string
          item_type?: string
          label?: string
          visit_template_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "template_scope_items_visit_template_id_fkey"
            columns: ["visit_template_id"]
            isOneToOne: false
            referencedRelation: "visit_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      user_site_roles: {
        Row: {
          granted_at: string
          granted_by: string | null
          id: string
          role_code: string
          site_id: string | null
          user_id: string
        }
        Insert: {
          granted_at?: string
          granted_by?: string | null
          id?: string
          role_code: string
          site_id?: string | null
          user_id: string
        }
        Update: {
          granted_at?: string
          granted_by?: string | null
          id?: string
          role_code?: string
          site_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_site_roles_role_code_fkey"
            columns: ["role_code"]
            isOneToOne: false
            referencedRelation: "role_definitions"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "user_site_roles_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_site_roles_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "v_dashboard_counters"
            referencedColumns: ["site_id"]
          },
        ]
      }
      visit_constraints: {
        Row: {
          affected_area: string | null
          cleaning_visit_id: string
          constraint_type: string
          created_at: string
          description: string
          id: string
        }
        Insert: {
          affected_area?: string | null
          cleaning_visit_id: string
          constraint_type: string
          created_at?: string
          description: string
          id?: string
        }
        Update: {
          affected_area?: string | null
          cleaning_visit_id?: string
          constraint_type?: string
          created_at?: string
          description?: string
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "visit_constraints_cleaning_visit_id_fkey"
            columns: ["cleaning_visit_id"]
            isOneToOne: false
            referencedRelation: "cleaning_visits"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visit_constraints_constraint_type_fkey"
            columns: ["constraint_type"]
            isOneToOne: false
            referencedRelation: "constraint_types"
            referencedColumns: ["code"]
          },
        ]
      }
      visit_focus_item_evidence: {
        Row: {
          caption: string | null
          created_at: string
          evidence_item_id: string
          visit_focus_item_id: string
        }
        Insert: {
          caption?: string | null
          created_at?: string
          evidence_item_id: string
          visit_focus_item_id: string
        }
        Update: {
          caption?: string | null
          created_at?: string
          evidence_item_id?: string
          visit_focus_item_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "visit_focus_item_evidence_evidence_item_id_fkey"
            columns: ["evidence_item_id"]
            isOneToOne: false
            referencedRelation: "evidence_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visit_focus_item_evidence_visit_focus_item_id_fkey"
            columns: ["visit_focus_item_id"]
            isOneToOne: false
            referencedRelation: "visit_focus_items"
            referencedColumns: ["id"]
          },
        ]
      }
      visit_focus_items: {
        Row: {
          cleaning_visit_id: string
          completed_at: string | null
          completion_note: string | null
          created_at: string
          description_snapshot: string | null
          display_order: number
          exact_location: string | null
          focus_item_id: string | null
          focus_name_snapshot: string
          id: string
          source_recommendation_id: string | null
          status: Database["public"]["Enums"]["focus_item_status"]
          updated_at: string
        }
        Insert: {
          cleaning_visit_id: string
          completed_at?: string | null
          completion_note?: string | null
          created_at?: string
          description_snapshot?: string | null
          display_order?: number
          exact_location?: string | null
          focus_item_id?: string | null
          focus_name_snapshot: string
          id?: string
          source_recommendation_id?: string | null
          status?: Database["public"]["Enums"]["focus_item_status"]
          updated_at?: string
        }
        Update: {
          cleaning_visit_id?: string
          completed_at?: string | null
          completion_note?: string | null
          created_at?: string
          description_snapshot?: string | null
          display_order?: number
          exact_location?: string | null
          focus_item_id?: string | null
          focus_name_snapshot?: string
          id?: string
          source_recommendation_id?: string | null
          status?: Database["public"]["Enums"]["focus_item_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "visit_focus_items_cleaning_visit_id_fkey"
            columns: ["cleaning_visit_id"]
            isOneToOne: false
            referencedRelation: "cleaning_visits"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visit_focus_items_focus_item_id_fkey"
            columns: ["focus_item_id"]
            isOneToOne: false
            referencedRelation: "focus_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visit_focus_items_source_recommendation_id_fkey"
            columns: ["source_recommendation_id"]
            isOneToOne: false
            referencedRelation: "visit_focus_recommendations"
            referencedColumns: ["id"]
          },
        ]
      }
      visit_focus_recommendations: {
        Row: {
          cleaning_visit_id: string
          created_at: string
          display_order: number
          focus_description_snapshot: string | null
          focus_item_id: string | null
          focus_label_snapshot: string
          id: string
          recommendation_status: string
          resolution_reason: string | null
          updated_at: string
        }
        Insert: {
          cleaning_visit_id: string
          created_at?: string
          display_order?: number
          focus_description_snapshot?: string | null
          focus_item_id?: string | null
          focus_label_snapshot: string
          id?: string
          recommendation_status?: string
          resolution_reason?: string | null
          updated_at?: string
        }
        Update: {
          cleaning_visit_id?: string
          created_at?: string
          display_order?: number
          focus_description_snapshot?: string | null
          focus_item_id?: string | null
          focus_label_snapshot?: string
          id?: string
          recommendation_status?: string
          resolution_reason?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "visit_focus_recommendations_cleaning_visit_id_fkey"
            columns: ["cleaning_visit_id"]
            isOneToOne: false
            referencedRelation: "cleaning_visits"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visit_focus_recommendations_focus_item_id_fkey"
            columns: ["focus_item_id"]
            isOneToOne: false
            referencedRelation: "focus_items"
            referencedColumns: ["id"]
          },
        ]
      }
      visit_rating_lines: {
        Row: {
          cleaning_visit_id: string
          created_at: string
          description_snapshot: string | null
          display_order: number
          id: string
          label_snapshot: string
          template_rating_line_id: string
          visit_template_id: string
        }
        Insert: {
          cleaning_visit_id: string
          created_at?: string
          description_snapshot?: string | null
          display_order?: number
          id?: string
          label_snapshot: string
          template_rating_line_id: string
          visit_template_id: string
        }
        Update: {
          cleaning_visit_id?: string
          created_at?: string
          description_snapshot?: string | null
          display_order?: number
          id?: string
          label_snapshot?: string
          template_rating_line_id?: string
          visit_template_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "visit_rating_lines_cleaning_visit_id_visit_template_id_fkey"
            columns: ["cleaning_visit_id", "visit_template_id"]
            isOneToOne: false
            referencedRelation: "cleaning_visits"
            referencedColumns: ["id", "visit_template_id"]
          },
          {
            foreignKeyName: "visit_rating_lines_template_rating_line_id_visit_template__fkey"
            columns: ["template_rating_line_id", "visit_template_id"]
            isOneToOne: false
            referencedRelation: "template_rating_lines"
            referencedColumns: ["id", "visit_template_id"]
          },
        ]
      }
      visit_scope_snapshots: {
        Row: {
          cleaning_visit_id: string
          created_at: string
          description_snapshot: string | null
          display_order: number
          id: string
          item_type: string
          label_snapshot: string
          source_template_scope_item_id: string | null
        }
        Insert: {
          cleaning_visit_id: string
          created_at?: string
          description_snapshot?: string | null
          display_order?: number
          id?: string
          item_type: string
          label_snapshot: string
          source_template_scope_item_id?: string | null
        }
        Update: {
          cleaning_visit_id?: string
          created_at?: string
          description_snapshot?: string | null
          display_order?: number
          id?: string
          item_type?: string
          label_snapshot?: string
          source_template_scope_item_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "visit_scope_snapshots_cleaning_visit_id_fkey"
            columns: ["cleaning_visit_id"]
            isOneToOne: false
            referencedRelation: "cleaning_visits"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visit_scope_snapshots_source_template_scope_item_id_fkey"
            columns: ["source_template_scope_item_id"]
            isOneToOne: false
            referencedRelation: "template_scope_items"
            referencedColumns: ["id"]
          },
        ]
      }
      visit_team_members: {
        Row: {
          cleaning_visit_id: string
          created_at: string
          full_name: string | null
          id: string
          role_on_visit: string
          user_id: string | null
        }
        Insert: {
          cleaning_visit_id: string
          created_at?: string
          full_name?: string | null
          id?: string
          role_on_visit: string
          user_id?: string | null
        }
        Update: {
          cleaning_visit_id?: string
          created_at?: string
          full_name?: string | null
          id?: string
          role_on_visit?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "visit_team_members_cleaning_visit_id_fkey"
            columns: ["cleaning_visit_id"]
            isOneToOne: false
            referencedRelation: "cleaning_visits"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visit_team_members_role_on_visit_fkey"
            columns: ["role_on_visit"]
            isOneToOne: false
            referencedRelation: "visit_team_role_options"
            referencedColumns: ["code"]
          },
        ]
      }
      visit_team_role_options: {
        Row: {
          code: string
          is_active: boolean
          label: string
          sort_order: number
        }
        Insert: {
          code: string
          is_active?: boolean
          label: string
          sort_order?: number
        }
        Update: {
          code?: string
          is_active?: boolean
          label?: string
          sort_order?: number
        }
        Relationships: []
      }
      visit_templates: {
        Row: {
          archived_at: string | null
          archived_by: string | null
          code: string
          created_at: string
          display_summary: string | null
          expected_weekday: number | null
          id: string
          name: string
          site_id: string
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          archived_by?: string | null
          code: string
          created_at?: string
          display_summary?: string | null
          expected_weekday?: number | null
          id?: string
          name: string
          site_id: string
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          archived_by?: string | null
          code?: string
          created_at?: string
          display_summary?: string | null
          expected_weekday?: number | null
          id?: string
          name?: string
          site_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "visit_templates_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visit_templates_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "v_dashboard_counters"
            referencedColumns: ["site_id"]
          },
        ]
      }
    }
    Views: {
      v_dashboard_counters: {
        Row: {
          actions_open: number | null
          actions_urgent_hs: number | null
          site_id: string | null
          site_name: string | null
          visits_awaiting_review: number | null
          visits_open: number | null
        }
        Insert: {
          actions_open?: never
          actions_urgent_hs?: never
          site_id?: string | null
          site_name?: string | null
          visits_awaiting_review?: never
          visits_open?: never
        }
        Update: {
          actions_open?: never
          actions_urgent_hs?: never
          site_id?: string | null
          site_name?: string | null
          visits_awaiting_review?: never
          visits_open?: never
        }
        Relationships: []
      }
    }
    Functions: {
      rpc_admin_reopen_visit_with_cancel: {
        Args: {
          p_cancel_draft_review_id: string
          p_reason: string
          p_visit_id: string
        }
        Returns: number
      }
      rpc_assign_site_role: {
        Args: { p_role_code: string; p_site_id: string; p_user_id: string }
        Returns: string
      }
      rpc_create_cleaning_visit_from_template: {
        Args: {
          p_rotation_programme_id?: string
          p_rotation_week_override?: number
          p_rotation_week_override_reason?: string
          p_site_id: string
          p_visit_date: string
          p_visit_template_id: string
          p_weekday_override_reason?: string
        }
        Returns: Json
      }
      rpc_create_superseding_review: {
        Args: { p_original_review_id: string; p_reason: string }
        Returns: string
      }
      rpc_finalise_evidence_upload: {
        Args: {
          p_caption?: string
          p_entity_id: string
          p_entity_kind: string
          p_storage_path: string
        }
        Returns: string
      }
      rpc_list_unfinalised_evidence: {
        Args: { p_older_than?: string; p_site_id: string }
        Returns: {
          byte_size: number
          created_at: string
          storage_path: string
        }[]
      }
      rpc_progress_action: {
        Args: {
          p_action_id: string
          p_assignee_id?: string
          p_expected_version: number
          p_new_status: Database["public"]["Enums"]["action_status"]
          p_note?: string
        }
        Returns: number
      }
      rpc_reopen_visit: {
        Args: { p_reason: string; p_visit_id: string }
        Returns: number
      }
      rpc_revoke_site_role: {
        Args: { p_assignment_id: string }
        Returns: undefined
      }
      rpc_save_review_draft: {
        Args: {
          p_expected_version: number
          p_payload: Json
          p_review_id: string
        }
        Returns: number
      }
      rpc_save_visit_draft: {
        Args: {
          p_expected_version: number
          p_payload: Json
          p_visit_id: string
        }
        Returns: number
      }
      rpc_set_rotation_anchor: {
        Args: { p_anchor_date: string; p_programme_id: string }
        Returns: undefined
      }
      rpc_site_user_directory: {
        Args: { p_site_id: string }
        Returns: {
          display_name: string
          role_code: string
          site_id: string
          user_id: string
        }[]
      }
      rpc_start_review_draft: {
        Args: {
          p_review_type?: Database["public"]["Enums"]["review_type"]
          p_visit_id: string
        }
        Returns: string
      }
      rpc_submit_review: {
        Args: { p_expected_version: number; p_review_id: string }
        Returns: string
      }
      rpc_submit_superseding_review: {
        Args: { p_expected_version: number; p_new_review_id: string }
        Returns: string
      }
      rpc_submit_supervisor_handover: {
        Args: { p_expected_version: number; p_visit_id: string }
        Returns: number
      }
    }
    Enums: {
      action_priority: "urgent" | "high" | "normal" | "low"
      action_status:
        | "open"
        | "assigned"
        | "in_progress"
        | "blocked"
        | "awaiting_verification"
        | "closed"
        | "cancelled"
      cleaning_visit_status:
        | "draft"
        | "planned"
        | "in_progress"
        | "submitted_for_review"
        | "reviewed"
        | "closed"
        | "cancelled"
      focus_item_status:
        | "selected"
        | "completed"
        | "partially_completed"
        | "not_completed"
        | "inaccessible"
        | "deferred"
        | "not_applicable"
      review_status: "draft" | "submitted" | "superseded"
      review_type: "dm_lightweight" | "joint_walk" | "ops_spot" | "gm_spot"
      scope_classification:
        | "routine_cleaning"
        | "rotating_focus"
        | "maintenance_site_fabric"
        | "access"
        | "equipment_chemical"
        | "out_of_scope"
        | "additional_resource"
        | "urgent_hs"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      action_priority: ["urgent", "high", "normal", "low"],
      action_status: [
        "open",
        "assigned",
        "in_progress",
        "blocked",
        "awaiting_verification",
        "closed",
        "cancelled",
      ],
      cleaning_visit_status: [
        "draft",
        "planned",
        "in_progress",
        "submitted_for_review",
        "reviewed",
        "closed",
        "cancelled",
      ],
      focus_item_status: [
        "selected",
        "completed",
        "partially_completed",
        "not_completed",
        "inaccessible",
        "deferred",
        "not_applicable",
      ],
      review_status: ["draft", "submitted", "superseded"],
      review_type: ["dm_lightweight", "joint_walk", "ops_spot", "gm_spot"],
      scope_classification: [
        "routine_cleaning",
        "rotating_focus",
        "maintenance_site_fabric",
        "access",
        "equipment_chemical",
        "out_of_scope",
        "additional_resource",
        "urgent_hs",
      ],
    },
  },
} as const
